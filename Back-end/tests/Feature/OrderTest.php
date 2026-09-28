<?php

namespace Tests\Feature;

use App\Domain\Ordering\OrderService;
use App\Domain\Ordering\OrderStatus;
use App\Models\Branch;
use App\Models\Merchant;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\Store;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * RESTAURANT ORDERS (RestaurantEngine, R3)
 *
 * The order path carries the same non-negotiable as the booking path: the
 * SERVER prices everything. These tests prove the total is computed from the
 * stored menu (never the client), that option rules are enforced at write
 * time, that a tampered option id is refused, that price snapshots survive a
 * later menu edit, and that the status machine only allows legal moves.
 * ============================================================================
 */
class OrderTest extends TestCase
{
    use RefreshDatabase;

    private Merchant $merchant;

    private Store $store;

    private User $owner;

    private MenuItem $burger;

    private int $sizeMid;

    private int $sizeLarge;

    private int $cheese;

    private int $bacon;

    protected function setUp(): void
    {
        parent::setUp();

        $this->merchant = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($this->merchant);

        $this->store = Store::factory()->create([
            'merchant_id' => $this->merchant->id,
            'business_type' => 'restaurant',
        ]);
        \App\Models\BookingSettings::create(array_merge(
            \App\Models\BookingSettings::defaults(),
            ['store_id' => $this->store->id],
        ));
        Branch::factory()->forStore($this->store)->create();

        $this->owner = User::factory()->create([
            'role' => 'merchant_owner', 'merchant_id' => $this->merchant->id,
        ]);

        $category = MenuCategory::create(['store_id' => $this->store->id, 'name_ar' => 'البرجر']);

        // برجر: base 30, required size (وسط +0 / كبير +5), optional extras
        // (جبن +3 / بيكون +6, choose up to 2).
        $this->burger = MenuItem::create([
            'store_id' => $this->store->id,
            'menu_category_id' => $category->id,
            'name_ar' => 'برجر', 'price' => 30,
        ]);

        $size = $this->burger->optionGroups()->create([
            'store_id' => $this->store->id, 'name_ar' => 'الحجم', 'min_select' => 1, 'max_select' => 1,
        ]);
        $this->sizeMid = $size->options()->create([
            'store_id' => $this->store->id, 'name_ar' => 'وسط', 'price_delta' => 0])->id;
        $this->sizeLarge = $size->options()->create([
            'store_id' => $this->store->id, 'name_ar' => 'كبير', 'price_delta' => 5])->id;

        $extras = $this->burger->optionGroups()->create([
            'store_id' => $this->store->id, 'name_ar' => 'الإضافات', 'min_select' => 0, 'max_select' => 2,
        ]);
        $this->cheese = $extras->options()->create([
            'store_id' => $this->store->id, 'name_ar' => 'جبن', 'price_delta' => 3])->id;
        $this->bacon = $extras->options()->create([
            'store_id' => $this->store->id, 'name_ar' => 'بيكون', 'price_delta' => 6])->id;

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

    private function asCustomer(): User
    {
        $user = User::factory()->create(['role' => 'customer']);
        \App\Models\Customer::factory()->create(['user_id' => $user->id]);

        return $user->fresh();
    }

    // ---- server-side pricing ----------------------------------------------

    public function test_the_total_is_computed_from_the_menu_not_the_client(): void
    {
        $order = $this->svc()->place(
            store: $this->freshStore(),
            lines: [
                ['item_id' => $this->burger->id, 'option_ids' => [$this->sizeLarge, $this->cheese], 'quantity' => 2],
            ],
            fulfillmentType: 'pickup',
        );

        // 30 base + 5 (كبير) + 3 (جبن) = 38, ×2 = 76.
        $this->assertSame(76.0, (float) $order->total);
        $this->assertSame(38.0, (float) $order->items->first()->unit_price);
    }

    public function test_a_line_snapshots_names_and_prices_as_sold(): void
    {
        $order = $this->svc()->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [$this->sizeLarge], 'quantity' => 1]],
            fulfillmentType: 'pickup',
        );

        $item = $order->items->first();
        $this->assertSame('برجر', $item->name);
        $this->assertSame('كبير', $item->options->first()->name);
        $this->assertSame('الحجم', $item->options->first()->group_name);

        // Editing the menu afterwards must NOT rewrite the order.
        app(TenantContext::class)->setTenant($this->merchant);
        $this->burger->update(['price' => 999, 'name_ar' => 'برجر مختلف']);
        app(TenantContext::class)->setTenant(null);

        $item->refresh();
        $this->assertSame('برجر', $item->name);
        $this->assertSame(35.0, (float) $item->unit_price);
    }

    // ---- option-rule enforcement ------------------------------------------

    public function test_a_required_group_with_no_selection_is_refused(): void
    {
        $this->expectException(\App\Domain\Ordering\Exceptions\OrderNotPlaceable::class);

        $this->svc()->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [], 'quantity' => 1]],
            fulfillmentType: 'pickup',
        );
    }

    public function test_exceeding_a_groups_max_is_refused(): void
    {
        $this->expectException(\App\Domain\Ordering\Exceptions\OrderNotPlaceable::class);

        // Size is single-choice — two size picks must fail.
        $this->svc()->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id,
                'option_ids' => [$this->sizeMid, $this->sizeLarge], 'quantity' => 1]],
            fulfillmentType: 'pickup',
        );
    }

    public function test_an_option_from_another_dish_is_refused(): void
    {
        // An option id that is not on this item at all (tampering / stale cart).
        $this->expectException(\App\Domain\Ordering\Exceptions\OrderNotPlaceable::class);

        $this->svc()->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id,
                'option_ids' => [$this->sizeMid, 999999], 'quantity' => 1]],
            fulfillmentType: 'pickup',
        );
    }

    public function test_a_sold_out_dish_cannot_be_ordered(): void
    {
        app(TenantContext::class)->setTenant($this->merchant);
        $this->burger->update(['is_available' => false]);
        app(TenantContext::class)->setTenant(null);

        $this->expectException(\App\Domain\Ordering\Exceptions\OrderNotPlaceable::class);

        $this->svc()->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [$this->sizeMid], 'quantity' => 1]],
            fulfillmentType: 'pickup',
        );
    }

    // ---- auto-accept -------------------------------------------------------

    public function test_auto_accept_moves_the_order_and_commits_prep_time(): void
    {
        app(TenantContext::class)->setTenant($this->merchant);
        $this->store->bookingSettings->update(['auto_accept_orders' => true, 'default_prep_minutes' => 25]);
        app(TenantContext::class)->setTenant(null);

        $order = $this->svc()->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [$this->sizeMid], 'quantity' => 1]],
            fulfillmentType: 'pickup',
        );

        $this->assertSame(OrderStatus::Accepted, $order->status);
        $this->assertSame(25, $order->prep_minutes);
    }

    // ---- the state machine -------------------------------------------------

    public function test_the_status_machine_allows_only_legal_moves(): void
    {
        $order = $this->svc()->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [$this->sizeMid], 'quantity' => 1]],
            fulfillmentType: 'pickup',
        );

        $order->transitionTo(OrderStatus::Accepted, 'merchant');
        $order->transitionTo(OrderStatus::Preparing, 'merchant');
        $order->transitionTo(OrderStatus::Ready, 'merchant');
        $order->transitionTo(OrderStatus::Completed, 'merchant');

        $this->assertTrue($order->status->isTerminal());

        // A terminal order cannot move again.
        $this->expectException(\App\Domain\Ordering\Exceptions\InvalidOrderTransition::class);
        $order->transitionTo(OrderStatus::Preparing, 'merchant');
    }

    // ---- the HTTP surface --------------------------------------------------

    public function test_a_customer_places_and_tracks_an_order(): void
    {
        $customer = $this->asCustomer();

        $response = $this->actingAs($customer)->postJson('/api/v1/orders', [
            'store_token' => $this->store->public_token,
            'fulfillment_type' => 'pickup',
            'items' => [
                ['item_id' => $this->burger->id, 'option_ids' => [$this->sizeLarge, $this->bacon], 'quantity' => 1],
            ],
        ]);

        $response->assertCreated()
            ->assertJsonPath('status', 'placed')
            ->assertJsonPath('total', 41); // 30 + 5 + 6 (JSON number)

        $id = $response->json('id');

        // The customer can see it in their active list.
        $this->actingAs($customer)->getJson('/api/v1/orders?filter=active')
            ->assertOk()->assertJsonCount(1, 'data');

        // ...and cancel it while still placed.
        $this->actingAs($customer)->postJson("/api/v1/orders/{$id}/cancel")
            ->assertOk()->assertJsonPath('status', 'cancelled');
    }

    public function test_the_merchant_accepts_then_advances_an_order(): void
    {
        $customer = $this->asCustomer();
        $id = $this->actingAs($customer)->postJson('/api/v1/orders', [
            'store_token' => $this->store->public_token,
            'fulfillment_type' => 'pickup',
            'items' => [['item_id' => $this->burger->id, 'option_ids' => [$this->sizeMid], 'quantity' => 1]],
        ])->json('id');

        $this->actingAs($this->owner);
        app(TenantContext::class)->setTenant($this->merchant);

        $this->postJson("/api/v1/merchant/orders/{$id}/status", ['status' => 'accepted', 'prep_minutes' => 15])
            ->assertOk()
            ->assertJsonPath('order.status', 'accepted')
            ->assertJsonPath('order.prep_minutes', 15);

        // An illegal jump (accepted → completed) is refused by the machine.
        $this->postJson("/api/v1/merchant/orders/{$id}/status", ['status' => 'completed'])
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'INVALID_ORDER_TRANSITION');
    }

    public function test_orders_are_tenant_isolated(): void
    {
        $customer = $this->asCustomer();
        $id = $this->actingAs($customer)->postJson('/api/v1/orders', [
            'store_token' => $this->store->public_token,
            'fulfillment_type' => 'pickup',
            'items' => [['item_id' => $this->burger->id, 'option_ids' => [$this->sizeMid], 'quantity' => 1]],
        ])->json('id');

        // Another merchant cannot see or touch it.
        $other = Merchant::factory()->create(['status' => 'approved']);
        $otherOwner = User::factory()->create(['role' => 'merchant_owner', 'merchant_id' => $other->id]);
        app(TenantContext::class)->setTenant($other);
        Store::factory()->create(['merchant_id' => $other->id, 'business_type' => 'restaurant']);

        $this->actingAs($otherOwner);
        app(TenantContext::class)->setTenant($other);

        $this->getJson('/api/v1/merchant/orders')->assertOk()->assertJsonCount(0, 'data');
        $this->postJson("/api/v1/merchant/orders/{$id}/status", ['status' => 'accepted'])
            ->assertNotFound();
    }
}
