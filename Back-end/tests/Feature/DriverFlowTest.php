<?php

namespace Tests\Feature;

use App\Domain\Ordering\OrderService;
use App\Domain\Ordering\OrderStatus;
use App\Models\Branch;
use App\Models\BookingSettings;
use App\Models\Customer;
use App\Models\CustomerAddress;
use App\Models\Driver;
use App\Models\Merchant;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\Store;
use App\Models\User;
use App\Models\WaslaNotification;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * DELIVERY DRIVERS (the "Easy App Driver" app)
 *
 * The merchant creates driver accounts from the dashboard; a driver signs in
 * with phone + password, sees ONLY their store's delivery orders, claims one
 * (first tap wins), takes it out for delivery, and the customer and merchant
 * follow the driver's live position until hand-over.
 * ============================================================================
 */
class DriverFlowTest extends TestCase
{
    use RefreshDatabase;

    private Merchant $merchant;

    private Store $store;

    private User $owner;

    private MenuItem $burger;

    protected function setUp(): void
    {
        parent::setUp();

        [$this->merchant, $this->store, $this->owner, $this->burger] = $this->makeShop();
    }

    // -- fixtures -------------------------------------------------------------

    /** @return array{Merchant, Store, User, MenuItem} */
    private function makeShop(): array
    {
        $merchant = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($merchant);

        $store = Store::factory()->create(['merchant_id' => $merchant->id, 'business_type' => 'restaurant']);
        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $store->id, 'order_delivery' => true, 'delivery_fee' => 10,
        ]));
        Branch::factory()->forStore($store)->create(['latitude' => 24.7136, 'longitude' => 46.6753]);

        $owner = User::factory()->create(['role' => 'merchant_owner', 'merchant_id' => $merchant->id]);

        $category = MenuCategory::create(['store_id' => $store->id, 'name_ar' => 'البرجر']);
        $burger = MenuItem::create([
            'store_id' => $store->id, 'menu_category_id' => $category->id, 'name_ar' => 'برجر', 'price' => 30,
        ]);

        app(TenantContext::class)->setTenant(null);

        return [$merchant, $store, $owner, $burger];
    }

    /** Creates a driver through the merchant API and returns [Driver, plain password]. */
    private function createDriver(User $owner, string $phone = '0551234567', string $name = 'سعد'): array
    {
        $password = 'driver-pass-123';
        $id = $this->actingAs($owner)->postJson('/api/v1/merchant/drivers', [
            'name' => $name, 'phone' => $phone, 'password' => $password, 'vehicle' => 'دراجة',
        ])->assertCreated()->json('id');

        app(TenantContext::class)->setTenant(null);

        return [Driver::withoutTenancy()->with('user')->find($id), $password];
    }

    private function driverToken(string $phone, string $password): string
    {
        return $this->postJson('/api/v1/auth/driver/login', ['phone' => $phone, 'password' => $password])
            ->assertOk()->json('token');
    }

    /** @return array{User, Order} a customer and their accepted delivery order */
    private function acceptedDeliveryOrder(?Store $store = null, ?MenuItem $item = null): array
    {
        $store ??= $this->store;
        $item ??= $this->burger;

        $user = User::factory()->create(['role' => 'customer']);
        $customer = Customer::factory()->create(['user_id' => $user->id]);
        $address = CustomerAddress::factory()->default()->create([
            'customer_id' => $customer->id, 'latitude' => 24.7236, 'longitude' => 46.6853,
        ]);

        $order = app(OrderService::class)->place(
            store: Store::query()->withoutGlobalScopes()->with('bookingSettings')->find($store->id),
            lines: [['item_id' => $item->id, 'option_ids' => [], 'quantity' => 1]],
            fulfillmentType: 'delivery',
            customer: $customer->fresh(),
            deliveryAddress: $address,
        );
        $order->transitionTo(OrderStatus::Accepted, 'merchant');

        return [$user->fresh(), $order->fresh()];
    }

    /**
     * Drive the next request with a real Sanctum token. actingAs() pins a user
     * on the guard for the rest of the test, so the guard is rebuilt first and
     * the bearer token is what authenticates — exactly like the driver app.
     */
    private function asDriver(string $token): static
    {
        $this->app['auth']->forgetGuards();

        return $this->withHeader('Authorization', "Bearer {$token}");
    }

    // -- accounts ---------------------------------------------------------------

    public function test_merchant_creates_a_driver_with_a_login(): void
    {
        [$driver] = $this->createDriver($this->owner);

        $this->assertSame('+966551234567', $driver->phone);
        $this->assertSame(User::ROLE_DRIVER, $driver->user->role);
        $this->assertSame($this->merchant->id, $driver->user->merchant_id);
        $this->assertSame($this->store->id, $driver->store_id);

        $this->actingAs($this->owner)->getJson('/api/v1/merchant/drivers')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.active_orders_count', 0);
    }

    public function test_driver_phone_is_unique_across_all_merchants(): void
    {
        $this->createDriver($this->owner);
        [, , $otherOwner] = $this->makeShop();

        $this->actingAs($otherOwner)->postJson('/api/v1/merchant/drivers', [
            'name' => 'آخر', 'phone' => '0551234567', 'password' => 'another-pass-1',
        ])->assertStatus(422)->assertJsonPath('error_code', 'VALIDATION_FAILED');
    }

    public function test_driver_logs_in_with_phone_and_password(): void
    {
        [, $password] = $this->createDriver($this->owner);

        $this->postJson('/api/v1/auth/driver/login', ['phone' => '0551234567', 'password' => 'wrong'])
            ->assertStatus(422)->assertJsonPath('error_code', 'INVALID_CREDENTIALS');

        $token = $this->driverToken('0551234567', $password);

        $this->asDriver($token)->getJson('/api/v1/driver/me')
            ->assertOk()
            ->assertJsonPath('driver.name', 'سعد')
            ->assertJsonPath('store.token', $this->store->public_token);
    }

    public function test_driver_token_cannot_reach_merchant_or_customer_routes(): void
    {
        [, $password] = $this->createDriver($this->owner);
        $token = $this->driverToken('0551234567', $password);

        $this->asDriver($token)->getJson('/api/v1/merchant/orders')->assertStatus(403);
        $this->asDriver($token)->getJson('/api/v1/merchant/drivers')->assertStatus(403);
    }

    public function test_merchant_login_rejects_driver_accounts(): void
    {
        [$driver, $password] = $this->createDriver($this->owner);

        $this->postJson('/api/v1/auth/login', ['email' => $driver->user->email, 'password' => $password])
            ->assertStatus(422);
    }

    public function test_deactivating_a_driver_revokes_sessions_and_blocks_login(): void
    {
        [$driver, $password] = $this->createDriver($this->owner);
        $token = $this->driverToken('0551234567', $password);

        $this->actingAs($this->owner)->putJson("/api/v1/merchant/drivers/{$driver->id}", ['is_active' => false])
            ->assertOk()->assertJsonPath('is_active', false);
        app(TenantContext::class)->setTenant(null);

        $this->flushHeaders();
        $this->asDriver($token)->getJson('/api/v1/driver/me')->assertStatus(401);
        $this->postJson('/api/v1/auth/driver/login', ['phone' => '0551234567', 'password' => $password])
            ->assertStatus(403)->assertJsonPath('error_code', 'ACCOUNT_DISABLED');
    }

    public function test_deleting_a_driver_keeps_order_history(): void
    {
        [$driver] = $this->createDriver($this->owner);
        [, $order] = $this->acceptedDeliveryOrder();
        $order->forceFill(['driver_id' => $driver->id])->save();

        $this->actingAs($this->owner)->deleteJson("/api/v1/merchant/drivers/{$driver->id}")->assertOk();

        $this->assertDatabaseMissing('drivers', ['id' => $driver->id]);
        $this->assertDatabaseMissing('users', ['id' => $driver->user_id]);
        $this->assertNull(Order::withoutTenancy()->find($order->id)->driver_id);
    }

    public function test_a_merchant_cannot_touch_another_merchants_driver(): void
    {
        [$driver] = $this->createDriver($this->owner);
        [, , $otherOwner] = $this->makeShop();

        $this->actingAs($otherOwner)->putJson("/api/v1/merchant/drivers/{$driver->id}", ['name' => 'x'])->assertStatus(404);
        $this->actingAs($otherOwner)->deleteJson("/api/v1/merchant/drivers/{$driver->id}")->assertStatus(404);
        $this->assertDatabaseHas('drivers', ['id' => $driver->id, 'name' => 'سعد']);
    }

    // -- the delivery run ---------------------------------------------------------

    public function test_full_delivery_run_claim_pickup_track_deliver(): void
    {
        [, $password] = $this->createDriver($this->owner);
        $token = $this->driverToken('0551234567', $password);
        [$customerUser, $order] = $this->acceptedDeliveryOrder();

        // 1. The accepted delivery order is on the "available" board.
        $this->asDriver($token)->getJson('/api/v1/driver/orders?filter=available')
            ->assertOk()->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $order->id)
            ->assertJsonPath('data.0.delivery.latitude', 24.7236);

        // 2. Claim it → it moves to "mine" and leaves "available".
        $this->asDriver($token)->postJson("/api/v1/driver/orders/{$order->id}/claim")
            ->assertOk()->assertJsonPath('driver.name', 'سعد');
        $this->asDriver($token)->getJson('/api/v1/driver/orders?filter=available')->assertJsonCount(0, 'data');
        $this->asDriver($token)->getJson('/api/v1/driver/orders?filter=mine')->assertJsonCount(1, 'data');

        // 3. Before pickup the customer sees the driver but no position.
        $this->actingAs($customerUser)->getJson("/api/v1/orders/{$order->id}/tracking")
            ->assertOk()
            ->assertJsonPath('status', 'accepted')
            ->assertJsonPath('driver.name', 'سعد')
            ->assertJsonPath('driver_location', null);

        // 4. Kitchen marks it ready → the driver is pinged.
        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/status", ['status' => 'ready'])->assertOk();
        app(TenantContext::class)->setTenant(null);
        $this->assertDatabaseHas('wasla_notifications', [
            'order_id' => $order->id, 'channel' => 'in_app', 'template_key' => 'driver_order_ready',
        ]);

        // 5. Driver picks up → out_for_delivery; the customer is told.
        $this->flushHeaders();
        $this->asDriver($token)->postJson("/api/v1/driver/orders/{$order->id}/status", ['status' => 'out_for_delivery'])
            ->assertOk()->assertJsonPath('status', 'out_for_delivery');
        $this->assertDatabaseHas('wasla_notifications', [
            'order_id' => $order->id, 'notifiable_id' => $customerUser->id, 'template_key' => 'order_out_for_delivery',
        ]);

        // 6. Heartbeat → the customer AND the merchant see the live position + ETA.
        $this->asDriver($token)->postJson('/api/v1/driver/location', [
            'latitude' => 24.7180, 'longitude' => 46.6800, 'heading' => 45, 'speed_kmh' => 30,
        ])->assertOk();

        $this->flushHeaders();
        $tracking = $this->actingAs($customerUser)->getJson("/api/v1/orders/{$order->id}/tracking")
            ->assertOk()
            ->assertJsonPath('status', 'out_for_delivery')
            ->assertJsonPath('driver_location.latitude', 24.718)
            ->assertJsonPath('driver_location.fresh', true)
            ->assertJsonPath('origin.latitude', 24.7136)
            ->json();
        $this->assertGreaterThan(0, $tracking['eta_minutes']);

        $this->actingAs($this->owner)->getJson("/api/v1/merchant/orders/{$order->id}/tracking")
            ->assertOk()->assertJsonPath('driver_location.longitude', 46.68);
        app(TenantContext::class)->setTenant(null);

        // 7. Hand-over → completed, position no longer exposed, run is in "past".
        $this->flushHeaders();
        $this->asDriver($token)->postJson("/api/v1/driver/orders/{$order->id}/status", ['status' => 'completed'])
            ->assertOk()->assertJsonPath('status', 'completed');
        $this->asDriver($token)->getJson('/api/v1/driver/orders?filter=past')->assertJsonCount(1, 'data');

        $this->flushHeaders();
        $this->actingAs($customerUser)->getJson("/api/v1/orders/{$order->id}/tracking")
            ->assertJsonPath('driver_location', null)
            ->assertJsonPath('status', 'completed');
    }

    public function test_first_driver_to_claim_wins(): void
    {
        [, $p1] = $this->createDriver($this->owner, '0551234567', 'سعد');
        [, $p2] = $this->createDriver($this->owner, '0557654321', 'فهد');
        [, $order] = $this->acceptedDeliveryOrder();

        $t1 = $this->driverToken('0551234567', $p1);
        $t2 = $this->driverToken('0557654321', $p2);

        $this->asDriver($t1)->postJson("/api/v1/driver/orders/{$order->id}/claim")->assertOk();
        $this->flushHeaders();
        $this->asDriver($t2)->postJson("/api/v1/driver/orders/{$order->id}/claim")
            ->assertStatus(409)->assertJsonPath('error_code', 'ORDER_ALREADY_TAKEN');

        // ...and the loser cannot advance or even open it.
        $this->asDriver($t2)->postJson("/api/v1/driver/orders/{$order->id}/status", ['status' => 'out_for_delivery'])->assertStatus(404);
        $this->asDriver($t2)->getJson("/api/v1/driver/orders/{$order->id}")->assertStatus(404);
    }

    public function test_placed_orders_are_not_claimable_yet(): void
    {
        [, $password] = $this->createDriver($this->owner);
        $token = $this->driverToken('0551234567', $password);
        [, $order] = $this->acceptedDeliveryOrder();
        $order->forceFill(['status' => 'placed'])->save();

        $this->asDriver($token)->getJson('/api/v1/driver/orders?filter=available')->assertJsonCount(0, 'data');
        $this->asDriver($token)->postJson("/api/v1/driver/orders/{$order->id}/claim")
            ->assertStatus(422)->assertJsonPath('error_code', 'ORDER_NOT_CLAIMABLE');
    }

    public function test_driver_cannot_skip_pickup(): void
    {
        [, $password] = $this->createDriver($this->owner);
        $token = $this->driverToken('0551234567', $password);
        [, $order] = $this->acceptedDeliveryOrder();

        $this->asDriver($token)->postJson("/api/v1/driver/orders/{$order->id}/claim")->assertOk();
        // accepted → completed directly is not a legal transition.
        $this->asDriver($token)->postJson("/api/v1/driver/orders/{$order->id}/status", ['status' => 'completed'])
            ->assertStatus(422)->assertJsonPath('error_code', 'INVALID_ORDER_TRANSITION');
        // Nor is "rejected" ever a driver's call.
        $this->asDriver($token)->postJson("/api/v1/driver/orders/{$order->id}/status", ['status' => 'rejected'])
            ->assertStatus(422);
    }

    public function test_drivers_see_only_their_own_stores_delivery_orders(): void
    {
        [, $password] = $this->createDriver($this->owner);
        $token = $this->driverToken('0551234567', $password);

        [, $otherStore, , $otherItem] = $this->makeShop();
        [, $foreign] = $this->acceptedDeliveryOrder($otherStore, $otherItem);

        $this->asDriver($token)->getJson('/api/v1/driver/orders?filter=available')->assertJsonCount(0, 'data');
        $this->asDriver($token)->getJson("/api/v1/driver/orders/{$foreign->id}")->assertStatus(404);
        $this->asDriver($token)->postJson("/api/v1/driver/orders/{$foreign->id}/claim")->assertStatus(404);
        $this->assertNull($foreign->fresh()->driver_id);
    }

    public function test_pickup_orders_never_reach_the_driver_board(): void
    {
        [, $password] = $this->createDriver($this->owner);
        $token = $this->driverToken('0551234567', $password);

        $user = User::factory()->create(['role' => 'customer']);
        $customer = Customer::factory()->create(['user_id' => $user->id]);
        $order = app(OrderService::class)->place(
            store: Store::query()->withoutGlobalScopes()->with('bookingSettings')->find($this->store->id),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [], 'quantity' => 1]],
            fulfillmentType: 'pickup',
            customer: $customer->fresh(),
        );
        $order->transitionTo(OrderStatus::Accepted, 'merchant');

        $this->asDriver($token)->getJson('/api/v1/driver/orders?filter=available')->assertJsonCount(0, 'data');
        $this->asDriver($token)->postJson("/api/v1/driver/orders/{$order->id}/claim")->assertStatus(404);
    }

    // -- merchant-side assignment ------------------------------------------------

    public function test_merchant_assigns_and_reassigns_a_driver(): void
    {
        [$saad] = $this->createDriver($this->owner, '0551234567', 'سعد');
        [$fahd] = $this->createDriver($this->owner, '0557654321', 'فهد');
        [, $order] = $this->acceptedDeliveryOrder();

        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/driver", ['driver_id' => $saad->id])
            ->assertOk()->assertJsonPath('driver.id', $saad->id);
        app(TenantContext::class)->setTenant(null);
        $this->assertDatabaseHas('wasla_notifications', [
            'order_id' => $order->id, 'notifiable_id' => $saad->user_id, 'template_key' => 'driver_assigned',
        ]);

        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/driver", ['driver_id' => $fahd->id])
            ->assertOk()->assertJsonPath('driver.id', $fahd->id);
        app(TenantContext::class)->setTenant(null);
        $this->assertSame($fahd->id, Order::withoutTenancy()->find($order->id)->driver_id);
    }

    public function test_merchant_cannot_assign_foreign_or_inactive_drivers(): void
    {
        [$mine] = $this->createDriver($this->owner);
        [, , $otherOwner] = $this->makeShop();
        [$theirs] = $this->createDriver($otherOwner, '0557654321', 'غريب');
        [, $order] = $this->acceptedDeliveryOrder();

        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/driver", ['driver_id' => $theirs->id])
            ->assertStatus(422)->assertJsonPath('error_code', 'DRIVER_NOT_FOUND');
        app(TenantContext::class)->setTenant(null);

        Driver::withoutTenancy()->whereKey($mine->id)->update(['is_active' => false]);
        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/driver", ['driver_id' => $mine->id])
            ->assertStatus(422)->assertJsonPath('error_code', 'DRIVER_NOT_FOUND');
    }

    public function test_merchant_cannot_assign_a_driver_to_a_placed_or_finished_order(): void
    {
        [$driver] = $this->createDriver($this->owner);
        [, $order] = $this->acceptedDeliveryOrder();

        $order->forceFill(['status' => 'placed'])->save();
        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/driver", ['driver_id' => $driver->id])
            ->assertStatus(422)->assertJsonPath('error_code', 'ORDER_NOT_ASSIGNABLE');
        app(TenantContext::class)->setTenant(null);

        $order->forceFill(['status' => 'completed'])->save();
        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/driver", ['driver_id' => $driver->id])
            ->assertStatus(422)->assertJsonPath('error_code', 'ORDER_NOT_ASSIGNABLE');
    }

    public function test_merchant_can_mark_out_for_delivery_itself(): void
    {
        [, $order] = $this->acceptedDeliveryOrder();

        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/status", ['status' => 'ready'])->assertOk();
        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/status", ['status' => 'out_for_delivery'])
            ->assertOk()->assertJsonPath('order.status', 'out_for_delivery');
        $this->actingAs($this->owner)->postJson("/api/v1/merchant/orders/{$order->id}/status", ['status' => 'completed'])
            ->assertOk()->assertJsonPath('order.status', 'completed');

        $this->assertNotNull(Order::withoutTenancy()->find($order->id)->out_for_delivery_at);
    }

    public function test_customer_cannot_track_someone_elses_order(): void
    {
        [, $order] = $this->acceptedDeliveryOrder();
        $stranger = User::factory()->create(['role' => 'customer']);
        Customer::factory()->create(['user_id' => $stranger->id]);

        $this->actingAs($stranger)->getJson("/api/v1/orders/{$order->id}/tracking")->assertStatus(404);
    }

    public function test_location_heartbeat_is_validated(): void
    {
        [, $password] = $this->createDriver($this->owner);
        $token = $this->driverToken('0551234567', $password);

        $this->asDriver($token)->postJson('/api/v1/driver/location', ['latitude' => 95, 'longitude' => 46])->assertStatus(422);
        $this->asDriver($token)->postJson('/api/v1/driver/location', ['latitude' => 24.7, 'longitude' => 46.7])->assertOk();

        $this->assertSame(0, WaslaNotification::query()->count()); // a heartbeat never notifies anyone
        $this->assertNotNull(Driver::withoutTenancy()->first()->last_located_at);
    }
}
