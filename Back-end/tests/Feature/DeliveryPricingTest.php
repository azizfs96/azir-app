<?php

namespace Tests\Feature;

use App\Domain\Ordering\DeliveryPricing;
use App\Domain\Ordering\Exceptions\OrderNotPlaceable;
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
 * DISTANCE-BASED DELIVERY PRICING
 *
 * The merchant picks a mode (fixed / per km / tiers) and an optional radius.
 * The SERVER prices every order from the branch pin → customer pin distance;
 * the cart's quote endpoint runs the same code so what the customer saw is
 * what they pay, and an out-of-range address is refused before and during
 * placement.
 * ============================================================================
 */
class DeliveryPricingTest extends TestCase
{
    use RefreshDatabase;

    /** Branch pin: Riyadh centre. */
    private const BRANCH_LAT = 24.7136;

    private const BRANCH_LNG = 46.6753;

    private Merchant $merchant;

    private Store $store;

    private Branch $branch;

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
            'delivery_road_factor' => 1.0, // straight-line km in tests for readable numbers
        ]));

        $this->branch = Branch::factory()->forStore($this->store)->create([
            'latitude' => self::BRANCH_LAT,
            'longitude' => self::BRANCH_LNG,
        ]);

        $category = MenuCategory::create(['store_id' => $this->store->id, 'name_ar' => 'البرجر']);
        $this->burger = MenuItem::create([
            'store_id' => $this->store->id,
            'menu_category_id' => $category->id,
            'name_ar' => 'برجر', 'price' => 30,
        ]);

        app(TenantContext::class)->setTenant(null);
    }

    // -- helpers ------------------------------------------------------------

    private function settings(array $patch): void
    {
        BookingSettings::withoutGlobalScopes()->where('store_id', $this->store->id)->update($patch);
    }

    private function freshStore(): Store
    {
        return Store::query()->withoutGlobalScopes()->with('bookingSettings')->find($this->store->id);
    }

    /** A customer whose address sits roughly `km` kilometres east of the branch. */
    private function customerAt(float $km): array
    {
        $user = User::factory()->create(['role' => 'customer']);
        $customer = Customer::factory()->create(['user_id' => $user->id]);
        // 1° of longitude ≈ 101.1 km at this latitude.
        $address = CustomerAddress::factory()->default()->create([
            'customer_id' => $customer->id,
            'latitude' => self::BRANCH_LAT,
            'longitude' => self::BRANCH_LNG + $km / 101.1,
        ]);

        return [$user->fresh(), $customer->fresh(), $address];
    }

    private function place(Customer $customer, CustomerAddress $address)
    {
        return app(OrderService::class)->place(
            store: $this->freshStore(),
            lines: [['item_id' => $this->burger->id, 'option_ids' => [], 'quantity' => 2]],
            fulfillmentType: 'delivery',
            customer: $customer,
            deliveryAddress: $address,
        );
    }

    // -- the maths ----------------------------------------------------------

    public function test_haversine_is_accurate(): void
    {
        // Riyadh → Jeddah, ≈ 844 km great-circle.
        $km = DeliveryPricing::haversineKm(24.7136, 46.6753, 21.4858, 39.1925);

        $this->assertEqualsWithDelta(844, $km, 5);
    }

    public function test_fixed_mode_charges_the_flat_fee_and_snapshots_distance(): void
    {
        [, $customer, $address] = $this->customerAt(6);

        $order = $this->place($customer, $address);

        $this->assertSame(15.0, (float) $order->delivery_fee);
        $this->assertEqualsWithDelta(6.0, (float) $order->delivery_distance_km, 0.2);
        $this->assertSame(75.0, (float) $order->total);
    }

    public function test_per_km_mode_prices_base_plus_distance(): void
    {
        $this->settings(['delivery_pricing_mode' => 'per_km', 'delivery_base_fee' => 5, 'delivery_fee_per_km' => 2]);
        [, $customer, $address] = $this->customerAt(10);

        $order = $this->place($customer, $address);

        $km = (float) $order->delivery_distance_km;
        $this->assertEqualsWithDelta(10.0, $km, 0.2);
        $this->assertSame(round(5 + 2 * $km, 2), (float) $order->delivery_fee);
    }

    public function test_road_factor_scales_the_straight_line_distance(): void
    {
        $this->settings(['delivery_road_factor' => 1.5]);
        [, $customer, $address] = $this->customerAt(10);

        $order = $this->place($customer, $address);

        $this->assertEqualsWithDelta(15.0, (float) $order->delivery_distance_km, 0.3);
    }

    public function test_tiers_pick_the_first_matching_band(): void
    {
        $this->settings([
            'delivery_pricing_mode' => 'tiers',
            'delivery_tiers' => json_encode([
                ['up_to_km' => 3, 'fee' => 5],
                ['up_to_km' => 8, 'fee' => 12],
            ]),
        ]);

        [, $near, $nearAddress] = $this->customerAt(2);
        [, $mid, $midAddress] = $this->customerAt(6);

        $this->assertSame(5.0, (float) $this->place($near, $nearAddress)->delivery_fee);
        $this->assertSame(12.0, (float) $this->place($mid, $midAddress)->delivery_fee);
    }

    public function test_beyond_the_last_tier_is_out_of_range(): void
    {
        $this->settings([
            'delivery_pricing_mode' => 'tiers',
            'delivery_tiers' => json_encode([['up_to_km' => 3, 'fee' => 5]]),
        ]);
        [, $customer, $address] = $this->customerAt(9);

        try {
            $this->place($customer, $address);
            $this->fail('Expected OUT_OF_DELIVERY_RANGE');
        } catch (OrderNotPlaceable $e) {
            $this->assertSame('OUT_OF_DELIVERY_RANGE', $e->errorCode);
        }
    }

    public function test_max_radius_refuses_far_addresses_in_any_mode(): void
    {
        $this->settings(['delivery_max_distance_km' => 5]);
        [, $customer, $address] = $this->customerAt(7);

        $this->expectException(OrderNotPlaceable::class);
        $this->place($customer, $address);
    }

    public function test_missing_pins_fall_back_to_the_flat_fee(): void
    {
        // A branch without coordinates can still deliver: flat fee, no distance.
        $this->branch->update(['latitude' => null, 'longitude' => null]);
        $this->settings(['delivery_pricing_mode' => 'per_km', 'delivery_base_fee' => 5, 'delivery_fee_per_km' => 2, 'delivery_max_distance_km' => 5]);
        [, $customer, $address] = $this->customerAt(40);

        $order = $this->place($customer, $address);

        $this->assertSame(15.0, (float) $order->delivery_fee);
        $this->assertNull($order->delivery_distance_km);
    }

    // -- the quote endpoint (what the cart shows BEFORE ordering) --------------

    public function test_quote_endpoint_matches_order_pricing(): void
    {
        $this->settings(['delivery_pricing_mode' => 'per_km', 'delivery_base_fee' => 5, 'delivery_fee_per_km' => 2]);
        [$user, $customer, $address] = $this->customerAt(10);

        $quote = $this->actingAs($user)
            ->getJson("/api/v1/me/delivery-quote?store_token={$this->store->public_token}&address_id={$address->id}")
            ->assertOk()
            ->assertJsonPath('allowed', true)
            ->assertJsonPath('mode', 'per_km')
            ->assertJsonPath('delivery_enabled', true)
            ->assertJsonPath('branch_id', $this->branch->id)
            ->json();

        $order = $this->place($customer, $address);

        $this->assertSame((float) $order->delivery_fee, (float) $quote['fee']);
        $this->assertSame((float) $order->delivery_distance_km, (float) $quote['distance_km']);
    }

    public function test_quote_reports_out_of_range_without_placing(): void
    {
        $this->settings(['delivery_max_distance_km' => 5]);
        [$user, , $address] = $this->customerAt(7);

        $this->actingAs($user)
            ->getJson("/api/v1/me/delivery-quote?store_token={$this->store->public_token}&address_id={$address->id}")
            ->assertOk()
            ->assertJsonPath('allowed', false)
            ->assertJsonPath('reason', 'OUT_OF_RANGE')
            ->assertJsonPath('max_distance_km', 5);
    }

    public function test_quote_refuses_another_customers_address(): void
    {
        [$user] = $this->customerAt(1);
        [, , $strangersAddress] = $this->customerAt(1);

        $this->actingAs($user)
            ->getJson("/api/v1/me/delivery-quote?store_token={$this->store->public_token}&address_id={$strangersAddress->id}")
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'ADDRESS_NOT_FOUND');
    }

    // -- merchant settings round-trip ------------------------------------------

    public function test_merchant_saves_tiers_and_storefront_exposes_them(): void
    {
        $owner = User::factory()->create(['role' => 'merchant_owner', 'merchant_id' => $this->merchant->id]);

        $this->actingAs($owner)->patchJson('/api/v1/merchant/settings/booking', [
            'delivery_pricing_mode' => 'tiers',
            'delivery_tiers' => [['up_to_km' => 3, 'fee' => 5], ['up_to_km' => 8, 'fee' => 12]],
            'delivery_max_distance_km' => 8,
        ])->assertOk();

        $saved = BookingSettings::withoutGlobalScopes()->where('store_id', $this->store->id)->first();
        $this->assertSame('tiers', $saved->delivery_pricing_mode);
        $this->assertCount(2, $saved->delivery_tiers);
        $this->assertSame(8.0, (float) $saved->delivery_max_distance_km);

        app(TenantContext::class)->setTenant(null);
        $this->getJson("/api/v1/stores/{$this->store->public_token}")
            ->assertOk()
            ->assertJsonPath('configuration.delivery_pricing_mode', 'tiers')
            ->assertJsonPath('configuration.delivery_tiers.1.fee', 12)
            ->assertJsonPath('configuration.delivery_max_distance_km', 8);
    }

    public function test_merchant_tiers_are_validated(): void
    {
        $owner = User::factory()->create(['role' => 'merchant_owner', 'merchant_id' => $this->merchant->id]);

        $this->actingAs($owner)->patchJson('/api/v1/merchant/settings/booking', [
            'delivery_pricing_mode' => 'per_mile',
        ])->assertStatus(422);

        $this->actingAs($owner)->patchJson('/api/v1/merchant/settings/booking', [
            'delivery_tiers' => [['up_to_km' => 3]],
        ])->assertStatus(422);
    }
}
