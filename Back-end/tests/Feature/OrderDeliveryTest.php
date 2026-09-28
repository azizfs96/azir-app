<?php

namespace Tests\Feature;

use App\Domain\Ordering\OrderService;
use App\Models\Branch;
use App\Models\BookingSettings;
use App\Models\Customer;
use App\Models\CustomerAddress;
use App\Models\Merchant;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Store;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * DELIVERY ORDERS (feature expansion)
 *
 * Delivery keeps every guarantee the order path already has, and adds two the
 * server owns: the fee is computed here (never the client's figure), and the
 * destination is pulled from the customer's OWN central addresses — an id that
 * is not theirs, or a store that does not offer delivery, is refused.
 * ============================================================================
 */
class OrderDeliveryTest extends TestCase
{
    use RefreshDatabase;

    private Merchant $merchant;

    private Store $store;

    private MenuItem $burger;

    protected function setUp(): void
    {
        parent::setUp();

        $this->merchant = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($this->merchant);

        $this->store = Store::factory()->create([
            'merchant_id' => $this->merchant->id,
            'business_type' => 'restaurant',
        ]);

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $this->store->id,
            'order_delivery' => true,
            'delivery_fee' => 15,
            'delivery_min_order' => 0,
        ]));

        Branch::factory()->forStore($this->store)->create();

        $category = MenuCategory::create(['store_id' => $this->store->id, 'name_ar' => 'البرجر']);
        $this->burger = MenuItem::create([
            'store_id' => $this->store->id,
            'menu_category_id' => $category->id,
            'name_ar' => 'برجر', 'price' => 30,
        ]);

        app(TenantContext::class)->setTenant(null);
    }

    private function svc(): OrderService
    {
        return app(OrderService::class);
    }

    private function freshStore(): Store
    {
        return Store::query()->withoutGlobalScopes()->with('bookingSettings')->find($this->store->id);
    }

    private function customerWithAddress(): array
    {
        $user = User::factory()->create(['role' => 'customer']);
        $customer = Customer::factory()->create(['user_id' => $user->id]);
        $address = CustomerAddress::factory()->default()->create([
            'customer_id' => $customer->id,
            'address_text' => 'حي الملقا، الرياض',
        ]);

        return [$user->fresh(), $customer->fresh(), $address];
    }

    private function line(): array
    {
        return [['item_id' => $this->burger->id, 'option_ids' => [], 'quantity' => 2]];
    }

    public function test_delivery_adds_the_server_fee_to_the_total(): void
    {
        [, $customer, $address] = $this->customerWithAddress();

        $order = $this->svc()->place(
            store: $this->freshStore(),
            lines: $this->line(),
            fulfillmentType: 'delivery',
            customer: $customer,
            deliveryAddress: $address,
        );

        // 30 × 2 = 60 subtotal, + 15 delivery = 75.
        $this->assertSame(60.0, (float) $order->subtotal);
        $this->assertSame(15.0, (float) $order->delivery_fee);
        $this->assertSame(75.0, (float) $order->total);
    }

    public function test_delivery_snapshots_the_destination(): void
    {
        [, $customer, $address] = $this->customerWithAddress();

        $order = $this->svc()->place(
            store: $this->freshStore(),
            lines: $this->line(),
            fulfillmentType: 'delivery',
            customer: $customer,
            deliveryAddress: $address,
        );

        $this->assertSame('حي الملقا، الرياض', $order->delivery_address);
        $this->assertSame($address->id, $order->customer_address_id);

        // Editing the address afterwards must NOT rewrite the order.
        $address->update(['address_text' => 'عنوان مختلف']);
        $order->refresh();
        $this->assertSame('حي الملقا، الرياض', $order->delivery_address);
    }

    public function test_delivery_requires_an_address(): void
    {
        [, $customer] = $this->customerWithAddress();

        $this->expectException(\App\Domain\Ordering\Exceptions\OrderNotPlaceable::class);

        $this->svc()->place(
            store: $this->freshStore(),
            lines: $this->line(),
            fulfillmentType: 'delivery',
            customer: $customer,
            deliveryAddress: null,
        );
    }

    public function test_an_address_from_another_customer_is_refused(): void
    {
        [, $customer] = $this->customerWithAddress();
        [, , $strangerAddress] = $this->customerWithAddress();

        $this->expectException(\App\Domain\Ordering\Exceptions\OrderNotPlaceable::class);

        $this->svc()->place(
            store: $this->freshStore(),
            lines: $this->line(),
            fulfillmentType: 'delivery',
            customer: $customer,
            deliveryAddress: $strangerAddress,
        );
    }

    public function test_delivery_is_refused_when_the_store_disables_it(): void
    {
        app(TenantContext::class)->setTenant($this->merchant);
        $this->store->bookingSettings->update(['order_delivery' => false]);
        app(TenantContext::class)->setTenant(null);

        [, $customer, $address] = $this->customerWithAddress();

        $this->expectException(\App\Domain\Ordering\Exceptions\OrderNotPlaceable::class);

        $this->svc()->place(
            store: $this->freshStore(),
            lines: $this->line(),
            fulfillmentType: 'delivery',
            customer: $customer,
            deliveryAddress: $address,
        );
    }

    public function test_a_subtotal_below_the_minimum_is_refused(): void
    {
        app(TenantContext::class)->setTenant($this->merchant);
        $this->store->bookingSettings->update(['delivery_min_order' => 200]);
        app(TenantContext::class)->setTenant(null);

        [, $customer, $address] = $this->customerWithAddress();

        $this->expectException(\App\Domain\Ordering\Exceptions\OrderNotPlaceable::class);

        $this->svc()->place(
            store: $this->freshStore(),
            lines: $this->line(), // 60 < 200
            fulfillmentType: 'delivery',
            customer: $customer,
            deliveryAddress: $address,
        );
    }

    public function test_the_http_endpoint_pulls_the_address_from_the_customer(): void
    {
        [$user, , $address] = $this->customerWithAddress();

        $response = $this->actingAs($user)->postJson('/api/v1/orders', [
            'store_token' => $this->store->public_token,
            'fulfillment_type' => 'delivery',
            'address_id' => $address->id,
            'items' => [['item_id' => $this->burger->id, 'quantity' => 1]],
        ]);

        $response->assertCreated()
            ->assertJsonPath('fulfillment_type', 'delivery')
            ->assertJsonPath('delivery_fee', 15)
            ->assertJsonPath('total', 45)
            ->assertJsonPath('delivery.address', 'حي الملقا، الرياض');
    }

    public function test_tracking_returns_the_same_unwrapped_shape_as_placing(): void
    {
        [$user] = $this->customerWithAddress();

        $id = $this->actingAs($user)->postJson('/api/v1/orders', [
            'store_token' => $this->store->public_token,
            'fulfillment_type' => 'pickup',
            'items' => [['item_id' => $this->burger->id, 'quantity' => 1]],
        ])->assertCreated()->json('id');

        $this->assertNotNull($id, 'Placing must return a top-level id (no data wrapper).');

        // The tracking screen decodes this with the SAME parser as placing, so
        // the shape must match: a top-level id/status, never wrapped in `data`.
        $this->actingAs($user)->getJson("/api/v1/orders/{$id}")
            ->assertOk()
            ->assertJsonPath('id', $id)
            ->assertJsonPath('status', 'placed');
    }

    public function test_the_http_endpoint_refuses_someone_elses_address(): void
    {
        [$user] = $this->customerWithAddress();
        [, , $strangerAddress] = $this->customerWithAddress();

        $this->actingAs($user)->postJson('/api/v1/orders', [
            'store_token' => $this->store->public_token,
            'fulfillment_type' => 'delivery',
            'address_id' => $strangerAddress->id,
            'items' => [['item_id' => $this->burger->id, 'quantity' => 1]],
        ])->assertStatus(422)->assertJsonPath('error_code', 'ADDRESS_NOT_FOUND');
    }
}
