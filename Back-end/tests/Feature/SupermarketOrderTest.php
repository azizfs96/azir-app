<?php

namespace Tests\Feature;

use App\Domain\Ordering\Exceptions\InvalidOrderTransition;
use App\Domain\Ordering\Exceptions\OrderNotPlaceable;
use App\Domain\Ordering\OrderService;
use App\Domain\Ordering\OrderStatus;
use App\Engines\BusinessEngineRegistry;
use App\Engines\Supermarket\SupermarketEngine;
use App\Models\Branch;
use App\Models\BookingSettings;
use App\Models\Customer;
use App\Models\CustomerAddress;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Merchant;
use App\Models\Order;
use App\Models\Store;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * THE SUPERMARKET VERTICAL
 *
 * Groceries reuse the catalogue and the order pipeline, but the engine owns
 * the differences: delivery only, paid on delivery, products with a unit /
 * compare-at price / stock, and a shorter status machine
 * (placed → preparing → out_for_delivery → completed) with no accept/ready.
 * ============================================================================
 */
class SupermarketOrderTest extends TestCase
{
    use RefreshDatabase;

    private Merchant $merchant;

    private Store $store;

    private User $owner;

    private MenuItem $milk;

    private MenuItem $eggs;

    protected function setUp(): void
    {
        parent::setUp();

        $this->merchant = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($this->merchant);

        $this->store = Store::factory()->create([
            'merchant_id' => $this->merchant->id,
            'business_type' => 'supermarket',
        ]);
        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $this->store->id,
            'order_pickup' => false, 'order_dine_in' => false, 'order_delivery' => true, 'order_curbside' => false,
            'delivery_fee' => 10,
        ]));
        Branch::factory()->forStore($this->store)->create(['latitude' => 24.7136, 'longitude' => 46.6753]);

        $this->owner = User::factory()->create(['role' => 'merchant_owner', 'merchant_id' => $this->merchant->id]);

        $dairy = MenuCategory::create(['store_id' => $this->store->id, 'name_ar' => 'الألبان']);
        $this->milk = MenuItem::create([
            'store_id' => $this->store->id, 'menu_category_id' => $dairy->id,
            'name_ar' => 'حليب طازج', 'price' => 6.5, 'compare_at_price' => 8, 'unit' => '1 لتر',
            'stock_quantity' => 10, 'is_featured' => true,
        ]);
        $this->eggs = MenuItem::create([
            'store_id' => $this->store->id, 'menu_category_id' => $dairy->id,
            'name_ar' => 'بيض', 'price' => 18, 'unit' => '12 حبة',
        ]);

        app(TenantContext::class)->setTenant(null);
    }

    private function freshStore(): Store
    {
        return Store::query()->withoutGlobalScopes()->with('bookingSettings')->find($this->store->id);
    }

    /** @return array{User, Customer, CustomerAddress} */
    private function customer(): array
    {
        $user = User::factory()->create(['role' => 'customer']);
        $customer = Customer::factory()->create(['user_id' => $user->id]);
        $address = CustomerAddress::factory()->default()->create(['customer_id' => $customer->id]);

        return [$user->fresh(), $customer->fresh(), $address];
    }

    private function place(Customer $customer, CustomerAddress $address, array $lines, string $type = 'delivery'): Order
    {
        return app(OrderService::class)->place(
            store: $this->freshStore(),
            lines: $lines,
            fulfillmentType: $type,
            customer: $customer,
            deliveryAddress: $address,
        );
    }

    // -- engine --------------------------------------------------------------

    public function test_business_type_resolves_the_supermarket_engine(): void
    {
        $engine = app(BusinessEngineRegistry::class)->for($this->freshStore());

        $this->assertInstanceOf(SupermarketEngine::class, $engine);
        $this->assertTrue($engine->takesOrders());
        $this->assertSame(['delivery'], $engine->fulfillmentTypes());
        $this->assertSame('cash_on_delivery', $engine->paymentMethod());
    }

    public function test_onboarding_accepts_supermarket_as_a_business_type(): void
    {
        $this->postJson('/api/v1/auth/merchant/register', [
            'business_name' => 'ماركت البركة', 'business_type' => 'supermarket', 'owner_name' => 'صاحب الماركت',
            'email' => 'owner@baraka.sa', 'phone' => '0551112233', 'password' => 'secret-pass-123',
        ])->assertCreated();

        $this->assertSame('supermarket', Store::withoutGlobalScopes()->latest('id')->first()->business_type);
    }

    // -- storefront -----------------------------------------------------------

    public function test_the_storefront_serves_products_with_grocery_fields(): void
    {
        $json = $this->getJson("/api/v1/stores/{$this->store->public_token}")->assertOk()->json();

        $this->assertSame('supermarket', $json['store']['type']);
        $this->assertSame(['menu', 'cart', 'payment', 'confirm'], array_column($json['flow'], 'step'));
        $this->assertSame('cash_on_delivery', $json['flow'][2]['mode']);

        // The engine's own configuration, not the beauty booking booleans.
        $this->assertTrue($json['configuration']['order_delivery']);
        $this->assertFalse($json['configuration']['order_pickup']);
        $this->assertFalse($json['configuration']['order_dine_in']);
        $this->assertEquals(10.0, $json['configuration']['delivery_fee']);

        $milk = collect($json['menu']['categories'][0]['items'])->firstWhere('name_ar', 'حليب طازج');
        $this->assertSame(6.5, $milk['price']);
        $this->assertEquals(8.0, $milk['compare_at_price']);
        $this->assertSame(19, $milk['discount_percent']);
        $this->assertSame('1 لتر', $milk['unit']);
        $this->assertSame(10, $milk['stock_quantity']);
        $this->assertTrue($milk['in_stock']);
        $this->assertTrue($milk['is_featured']);
    }

    // -- ordering ---------------------------------------------------------------

    public function test_a_grocery_order_is_delivery_only_and_paid_on_delivery(): void
    {
        [, $customer, $address] = $this->customer();

        $order = $this->place($customer, $address, [['item_id' => $this->milk->id, 'option_ids' => [], 'quantity' => 2]]);

        $this->assertSame('delivery', $order->fulfillment_type);
        $this->assertSame('cash_on_delivery', $order->payment_method);
        $this->assertSame(13.0, (float) $order->subtotal);
        $this->assertSame(10.0, (float) $order->delivery_fee);
        $this->assertSame(23.0, (float) $order->total);
    }

    public function test_pickup_is_refused_for_a_supermarket(): void
    {
        [, $customer, $address] = $this->customer();

        try {
            $this->place($customer, $address, [['item_id' => $this->eggs->id, 'option_ids' => [], 'quantity' => 1]], 'pickup');
            $this->fail('pickup should be refused');
        } catch (OrderNotPlaceable $e) {
            $this->assertSame('FULFILLMENT_UNAVAILABLE', $e->errorCode);
        }
    }

    public function test_pickup_is_refused_over_http_too(): void
    {
        [$user] = $this->customer();

        $this->actingAs($user)->postJson('/api/v1/orders', [
            'store_token' => $this->store->public_token,
            'fulfillment_type' => 'pickup',
            'items' => [['item_id' => $this->eggs->id, 'quantity' => 1]],
        ])->assertStatus(422)->assertJsonPath('error_code', 'FULFILLMENT_UNAVAILABLE');
    }

    public function test_stock_is_decremented_and_runs_out(): void
    {
        [, $customer, $address] = $this->customer();

        $this->place($customer, $address, [['item_id' => $this->milk->id, 'option_ids' => [], 'quantity' => 7]]);
        $this->assertSame(3, $this->milk->fresh()->stock_quantity);

        try {
            $this->place($customer, $address, [['item_id' => $this->milk->id, 'option_ids' => [], 'quantity' => 4]]);
            $this->fail('over-selling should be refused');
        } catch (OrderNotPlaceable $e) {
            $this->assertSame('OUT_OF_STOCK', $e->errorCode);
        }
        // Nothing was taken by the refused order.
        $this->assertSame(3, $this->milk->fresh()->stock_quantity);

        // Untracked products (null) never run out.
        $this->place($customer, $address, [['item_id' => $this->eggs->id, 'option_ids' => [], 'quantity' => 40]]);
        $this->assertNull($this->eggs->fresh()->stock_quantity);
    }

    public function test_a_product_at_zero_stock_reads_as_sold_out_on_the_storefront(): void
    {
        MenuItem::withoutTenancy()->whereKey($this->milk->id)->update(['stock_quantity' => 0]);

        $json = $this->getJson("/api/v1/stores/{$this->store->public_token}")->assertOk()->json();
        $milk = collect($json['menu']['categories'][0]['items'])->firstWhere('name_ar', 'حليب طازج');

        $this->assertFalse($milk['in_stock']);
    }

    // -- the grocery status machine -------------------------------------------------

    public function test_grocery_orders_go_placed_preparing_out_for_delivery_completed(): void
    {
        [, $customer, $address] = $this->customer();
        $order = $this->place($customer, $address, [['item_id' => $this->eggs->id, 'option_ids' => [], 'quantity' => 1]]);

        $this->assertSame([OrderStatus::Preparing, OrderStatus::Rejected, OrderStatus::Cancelled], $order->allowedTransitions());

        // "accepted" and "ready" are not grocery steps.
        try {
            $order->transitionTo(OrderStatus::Accepted, 'merchant');
            $this->fail('accepted is not a grocery step');
        } catch (InvalidOrderTransition) {
        }

        $order->transitionTo(OrderStatus::Preparing, 'merchant');
        $order->transitionTo(OrderStatus::OutForDelivery, 'merchant');
        $order->transitionTo(OrderStatus::Completed, 'driver');

        $this->assertSame('completed', $order->fresh()->status->value);
        $this->assertNotNull($order->fresh()->out_for_delivery_at);
        $this->assertNotNull($order->fresh()->completed_at);
    }

    public function test_the_merchant_api_follows_the_grocery_machine(): void
    {
        [, $customer, $address] = $this->customer();
        $order = $this->place($customer, $address, [['item_id' => $this->eggs->id, 'option_ids' => [], 'quantity' => 1]]);

        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/status", ['status' => 'accepted'])
            ->assertStatus(422)->assertJsonPath('error_code', 'INVALID_ORDER_TRANSITION');

        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/status", ['status' => 'preparing'])
            ->assertOk()
            ->assertJsonPath('order.status', 'preparing')
            ->assertJsonPath('order.payment_method', 'cash_on_delivery')
            ->assertJsonPath('allowed_transitions', ['out_for_delivery', 'cancelled']);

        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/status", ['status' => 'out_for_delivery'])
            ->assertOk()->assertJsonPath('order.status', 'out_for_delivery');
    }

    public function test_restaurants_keep_their_own_machine(): void
    {
        Store::withoutGlobalScopes()->whereKey($this->store->id)->update(['business_type' => 'restaurant']);
        BookingSettings::withoutGlobalScopes()->where('store_id', $this->store->id)->update(['order_pickup' => true]);
        [, $customer, $address] = $this->customer();

        $order = app(OrderService::class)->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->eggs->id, 'option_ids' => [], 'quantity' => 1]],
            fulfillmentType: 'pickup',
            customer: $customer,
        );

        $this->assertSame('pay_at_store', $order->payment_method);
        $this->expectException(InvalidOrderTransition::class);
        $order->transitionTo(OrderStatus::Preparing, 'merchant'); // restaurants accept first
    }

    // -- merchant catalogue ------------------------------------------------------------

    public function test_the_merchant_saves_grocery_fields_on_a_product(): void
    {
        $id = $this->actingAs($this->owner)->postJson('/api/v1/merchant/menu/items', [
            'name_ar' => 'أرز بسمتي', 'price' => 45, 'compare_at_price' => 52, 'unit' => '5 كجم', 'stock_quantity' => 20,
        ])->assertCreated()->assertJsonPath('unit', '5 كجم')->assertJsonPath('discount_percent', 13)->json('id');

        $this->actingAs($this->owner)->putJson("/api/v1/merchant/menu/items/{$id}", ['compare_at_price' => 40])
            ->assertStatus(422); // a "was" price below the price is not a discount

        $this->actingAs($this->owner)->putJson("/api/v1/merchant/menu/items/{$id}", ['stock_quantity' => null])
            ->assertOk()->assertJsonPath('stock_quantity', null)->assertJsonPath('in_stock', true);
    }

    public function test_the_grocery_dashboard_summarises_orders_and_stock(): void
    {
        [, $customer, $address] = $this->customer();
        $order = $this->place($customer, $address, [['item_id' => $this->milk->id, 'option_ids' => [], 'quantity' => 6]]);
        $order->transitionTo(OrderStatus::Preparing, 'merchant');
        $order->transitionTo(OrderStatus::OutForDelivery, 'merchant');
        $order->transitionTo(OrderStatus::Completed, 'driver');
        $this->place($customer, $address, [['item_id' => $this->eggs->id, 'option_ids' => [], 'quantity' => 1]]);

        $json = $this->actingAs($this->owner)->getJson('/api/v1/merchant/grocery/dashboard')->assertOk()->json();

        $this->assertSame(1, $json['today']['new']);
        $this->assertSame(1, $json['today']['delivered']);
        $this->assertSame(2, $json['today']['orders']);
        $this->assertEquals(49.0, $json['revenue']['today']); // 6 × 6.5 + 10 delivery
        $this->assertSame('حليب طازج', $json['catalog']['low_stock'][0]['name']); // 10 − 6 = 4 ≤ 5
        $this->assertSame(6, $json['best_sellers'][0]['quantity']);
        $this->assertCount(1, $json['needs_action']);
    }

    public function test_publishing_a_supermarket_needs_products_not_services(): void
    {
        $empty = Store::factory()->create(['merchant_id' => $this->merchant->id, 'business_type' => 'supermarket']);
        $blockers = app(\App\Domain\Merchant\MerchantOnboardingService::class)->blockersFor($empty);

        $this->assertContains('catalog_required', $blockers);
        $this->assertNotContains('service_required', $blockers);
    }
}
