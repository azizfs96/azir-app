<?php

namespace Tests\Feature;

use App\Domain\Ordering\OrderService;
use App\Models\Branch;
use App\Models\BookingSettings;
use App\Models\Customer;
use App\Models\CustomerCar;
use App\Models\Merchant;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Store;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * CURBSIDE CARS (feature expansion — "من السيارة"). Cars are central to the
 * customer; a curbside order pulls the customer's own car, snapshots it, and
 * refuses a car that is not theirs.
 */
class CustomerCarTest extends TestCase
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
            'order_curbside' => true,
        ]));
        Branch::factory()->forStore($this->store)->create();

        $category = MenuCategory::create(['store_id' => $this->store->id, 'name_ar' => 'برجر']);
        $this->burger = MenuItem::create([
            'store_id' => $this->store->id, 'menu_category_id' => $category->id,
            'name_ar' => 'برجر', 'price' => 30,
        ]);

        app(TenantContext::class)->setTenant(null);
    }

    private function customer(): User
    {
        $user = User::factory()->create(['role' => 'customer']);
        Customer::factory()->create(['user_id' => $user->id]);

        return $user->fresh();
    }

    private function freshStore(): Store
    {
        return Store::query()->withoutGlobalScopes()->with('bookingSettings')->find($this->store->id);
    }

    public function test_the_first_saved_car_becomes_the_default(): void
    {
        $user = $this->customer();

        $this->actingAs($user)->postJson('/api/v1/me/cars', [
            'brand' => 'تويوتا', 'color' => 'أبيض', 'plate_letters' => 'أ ب ج', 'plate_numbers' => '4592',
        ])->assertCreated()->assertJsonPath('is_default', true);
    }

    public function test_a_customer_only_sees_their_own_cars(): void
    {
        $mine = $this->customer();
        $other = $this->customer();

        $this->actingAs($mine)->postJson('/api/v1/me/cars', [
            'brand' => 'لكزس', 'color' => 'أسود', 'plate_letters' => 'د هـ و', 'plate_numbers' => '1122',
        ])->assertCreated();
        $this->actingAs($other)->postJson('/api/v1/me/cars', [
            'brand' => 'كيا', 'color' => 'أحمر', 'plate_letters' => 'ز ح ط', 'plate_numbers' => '3344',
        ])->assertCreated();

        $this->actingAs($mine)->getJson('/api/v1/me/cars')
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.brand', 'لكزس');
    }

    public function test_a_curbside_order_snapshots_the_car(): void
    {
        $user = $this->customer();
        $customer = $user->customer;
        $car = CustomerCar::factory()->default()->create([
            'customer_id' => $customer->id, 'brand' => 'تويوتا', 'color' => 'أبيض',
            'plate_letters' => 'أ ب ج', 'plate_numbers' => '4592',
        ]);

        $order = app(OrderService::class)->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [], 'quantity' => 1]],
            fulfillmentType: 'curbside',
            customer: $customer,
            car: $car,
        );

        $this->assertSame($car->id, $order->customer_car_id);
        $this->assertStringContainsString('تويوتا', $order->car_description);

        // Editing the car later must not rewrite the order.
        $car->update(['brand' => 'نيسان']);
        $order->refresh();
        $this->assertStringContainsString('تويوتا', $order->car_description);
    }

    public function test_a_car_from_another_customer_is_refused(): void
    {
        $user = $this->customer();
        $stranger = $this->customer();
        $strangerCar = CustomerCar::factory()->create(['customer_id' => $stranger->customer->id]);

        $this->expectException(\App\Domain\Ordering\Exceptions\OrderNotPlaceable::class);

        app(OrderService::class)->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [], 'quantity' => 1]],
            fulfillmentType: 'curbside',
            customer: $user->customer,
            car: $strangerCar,
        );
    }

    public function test_the_http_endpoint_places_a_curbside_order_with_the_car(): void
    {
        $user = $this->customer();
        $car = CustomerCar::factory()->default()->create(['customer_id' => $user->customer->id]);

        $this->actingAs($user)->postJson('/api/v1/orders', [
            'store_token' => $this->store->public_token,
            'fulfillment_type' => 'curbside',
            'car_id' => $car->id,
            'items' => [['item_id' => $this->burger->id, 'quantity' => 1]],
        ])->assertCreated()->assertJsonPath('fulfillment_type', 'curbside');
    }
}
