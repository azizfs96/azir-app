<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\BookingSettings;
use App\Models\Branch;
use App\Models\CustomerStore;
use App\Models\Merchant;
use App\Models\QrScan;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * THE CORE PRODUCT JOURNEY (spec §41, §46)
 *
 *   Scan QR -> Wasla -> Merchant -> Service -> [Staff] -> Date -> Time -> Confirmed
 *
 * Plus the guarantees that make Wasla NOT a marketplace: a customer only ever
 * sees stores they personally scanned, and no endpoint exists to find others.
 * ============================================================================
 */
class CustomerJourneyTest extends TestCase
{
    use RefreshDatabase;

    private Store $glow;

    private Service $hairColor;

    private Staff $sara;

    protected function setUp(): void
    {
        parent::setUp();

        $merchant = Merchant::factory()->create(['display_name' => 'Glow Beauty']);
        app(TenantContext::class)->setTenant($merchant);

        $this->glow = Store::factory()->create([
            'merchant_id' => $merchant->id,
            'name_en' => 'Glow Beauty',
            'name_ar' => 'جلو بيوتي',
        ]);

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $this->glow->id,
            'staff_selection' => true,
            'min_lead_time_minutes' => 0,
            'max_advance_days' => 365,
        ]));

        $branch = Branch::factory()->forStore($this->glow)->create(['slot_interval_minutes' => 30]);

        foreach (range(0, 6) as $day) {
            $branch->schedules()->create([
                'day_of_week' => $day, 'opens_at' => '10:00', 'closes_at' => '22:00',
            ]);
        }

        $this->sara = Staff::factory()->forStore($this->glow)->create([
            'name' => 'Sara', 'branch_id' => $branch->id,
        ]);

        foreach (range(0, 6) as $day) {
            $this->sara->schedules()->create([
                'day_of_week' => $day, 'starts_at' => '10:00', 'ends_at' => '22:00',
            ]);
        }

        $this->hairColor = Service::factory()->forStore($this->glow)->create([
            'name_en' => 'Hair Color', 'duration_minutes' => 120, 'price' => 250,
            'buffer_after_minutes' => 0,
        ]);

        // Reset tenant: customers browse with NO tenant context.
        app(TenantContext::class)->setTenant(null);
    }

    private function signIn(string $phone = '0512345678'): string
    {
        $this->app['auth']->forgetGuards();
        $this->postJson('/api/v1/auth/otp/request', ['phone' => $phone]);

        return $this->postJson('/api/v1/auth/otp/verify', [
            'phone' => $phone, 'code' => '1111', 'first_name' => 'Abdulaziz',
        ])->json('token');
    }

    // =====================================================================
    // Scanning a QR
    // =====================================================================

    public function test_scanning_a_qr_resolves_the_store_without_signing_in(): void
    {
        // Someone standing outside a salon should see the storefront first.
        $this->withHeaders(['Accept-Language' => 'ar'])
            ->getJson("/api/v1/stores/{$this->glow->public_token}")
            ->assertOk()
            ->assertJsonPath('store.name', 'جلو بيوتي')
            ->assertJsonPath('store.token', $this->glow->public_token)
            ->assertJsonStructure(['store', 'configuration', 'flow', 'services', 'policies']);

        // English clients get the English name from the same endpoint (§33).
        $this->withHeaders(['Accept-Language' => 'en'])
            ->getJson("/api/v1/stores/{$this->glow->public_token}")
            ->assertJsonPath('store.name', 'Glow Beauty');
    }

    public function test_an_unknown_token_is_not_found(): void
    {
        $this->getJson('/api/v1/stores/ZZZZZZZZ')
            ->assertStatus(404)
            ->assertJsonPath('error_code', 'STORE_NOT_FOUND');
    }

    /**
     * An unpublished store and a suspended merchant must be indistinguishable
     * from a bad code — a scanner should not learn that a business exists.
     */
    public function test_an_unpublished_store_is_not_reachable(): void
    {
        $this->glow->forceFill(['is_published' => false])->save();

        $this->getJson("/api/v1/stores/{$this->glow->public_token}")->assertStatus(404);
    }

    public function test_a_suspended_merchants_store_is_not_reachable(): void
    {
        $this->glow->merchant->forceFill(['status' => Merchant::STATUS_SUSPENDED])->save();

        $this->getJson("/api/v1/stores/{$this->glow->public_token}")->assertStatus(404);
    }

    public function test_a_scan_is_recorded_for_analytics(): void
    {
        $this->getJson("/api/v1/stores/{$this->glow->public_token}")->assertOk();

        $this->assertSame(1, QrScan::query()->withoutTenancy()->count());
    }

    public function test_the_flow_adapts_to_the_merchants_configuration(): void
    {
        $withStaff = $this->getJson("/api/v1/stores/{$this->glow->public_token}")
            ->json('flow.*.step');

        $this->assertContains('staff', $withStaff);

        // Turn staff selection off — the step must disappear entirely.
        $this->glow->bookingSettings->update(['staff_selection' => false]);

        $withoutStaff = $this->getJson("/api/v1/stores/{$this->glow->public_token}")
            ->json('flow.*.step');

        $this->assertNotContains('staff', $withoutStaff);
    }

    public function test_the_roster_is_withheld_when_staff_selection_is_off(): void
    {
        $this->glow->bookingSettings->update(['staff_selection' => false]);

        // Not merely hidden in the UI — never sent at all.
        $this->getJson("/api/v1/stores/{$this->glow->public_token}")
            ->assertOk()
            ->assertJsonPath('staff', []);
    }

    // =====================================================================
    // The booking journey
    // =====================================================================

    public function test_the_whole_journey_from_scan_to_confirmation(): void
    {
        $token = $this->signIn();
        $date = CarbonImmutable::now('Asia/Riyadh')->addDays(3)->format('Y-m-d');

        // Scan.
        $this->getJson("/api/v1/stores/{$this->glow->public_token}")->assertOk();

        // Pick a time.
        $slots = $this->getJson(
            "/api/v1/stores/{$this->glow->public_token}/availability?service_id={$this->hairColor->id}&date={$date}"
        )->assertOk()->json('days.0.slots');

        $this->assertNotEmpty($slots);

        // Book.
        $response = $this->withToken($token)->postJson('/api/v1/bookings', [
            'store_token' => $this->glow->public_token,
            'service_id' => $this->hairColor->id,
            'starts_at' => $slots[0]['starts_at'],
            'staff_id' => $slots[0]['staff_id'],
            'notes' => 'First visit',
        ]);

        $response->assertCreated()
            ->assertJsonPath('status', 'confirmed')
            ->assertJsonPath('price', fn ($price) => (float) $price === 250.0)
            ->assertJsonPath('can_cancel', true);

        $this->assertStringStartsWith('WSL-', $response->json('reference'));

        // Booking a store puts it in My Stores.
        $this->assertDatabaseHas('customer_stores', [
            'store_id' => $this->glow->id,
            'added_via' => 'booking',
        ]);
    }

    public function test_the_same_slot_cannot_be_booked_twice(): void
    {
        $token = $this->signIn();
        $date = CarbonImmutable::now('Asia/Riyadh')->addDays(3)->format('Y-m-d');

        $slot = $this->getJson(
            "/api/v1/stores/{$this->glow->public_token}/availability?service_id={$this->hairColor->id}&date={$date}"
        )->json('days.0.slots.0');

        $payload = [
            'store_token' => $this->glow->public_token,
            'service_id' => $this->hairColor->id,
            'starts_at' => $slot['starts_at'],
            'staff_id' => $slot['staff_id'],
        ];

        $this->withToken($token)->postJson('/api/v1/bookings', $payload)->assertCreated();

        $this->withToken($token)->postJson('/api/v1/bookings', $payload)
            ->assertStatus(409)
            ->assertJsonPath('error_code', 'SLOT_TAKEN');
    }

    public function test_booking_requires_authentication(): void
    {
        $this->postJson('/api/v1/bookings', [
            'store_token' => $this->glow->public_token,
            'service_id' => $this->hairColor->id,
            'starts_at' => CarbonImmutable::now()->addDays(3)->toIso8601String(),
        ])->assertStatus(401);
    }

    /**
     * A service id belonging to a DIFFERENT merchant must not be bookable
     * through this store's token.
     */
    public function test_a_service_from_another_merchant_cannot_be_booked(): void
    {
        $other = Merchant::factory()->create();
        app(TenantContext::class)->setTenant($other);
        $otherStore = Store::factory()->create(['merchant_id' => $other->id]);
        $otherService = Service::factory()->forStore($otherStore)->create();
        app(TenantContext::class)->setTenant(null);

        $token = $this->signIn();

        $this->withToken($token)->postJson('/api/v1/bookings', [
            'store_token' => $this->glow->public_token,
            'service_id' => $otherService->id,
            'starts_at' => CarbonImmutable::now('Asia/Riyadh')->addDays(3)->setTime(12, 0)->toIso8601String(),
        ])
            ->assertStatus(404)
            ->assertJsonPath('error_code', 'SERVICE_NOT_FOUND');
    }

    /**
     * Spec §9: when the merchant hides staff, a client-supplied staff_id must
     * be ignored rather than obeyed.
     */
    public function test_a_staff_id_is_ignored_when_the_merchant_hides_staff(): void
    {
        $this->glow->bookingSettings->update(['staff_selection' => false]);
        $token = $this->signIn();

        $response = $this->withToken($token)->postJson('/api/v1/bookings', [
            'store_token' => $this->glow->public_token,
            'service_id' => $this->hairColor->id,
            'starts_at' => CarbonImmutable::now('Asia/Riyadh')->addDays(3)->setTime(12, 0)->toIso8601String(),
            'staff_id' => $this->sara->id,
        ]);

        $response->assertCreated();

        // The backend still assigned someone — it just was not the customer's call.
        $booking = Booking::query()->withoutTenancy()->firstOrFail();
        $this->assertNotNull($booking->staff_id);
        $this->assertNull($response->json('staff'), 'Staff identity was exposed while hidden');
    }

    // =====================================================================
    // Cancellation (spec §21)
    // =====================================================================

    public function test_a_customer_can_cancel_within_the_deadline(): void
    {
        $token = $this->signIn();
        $booking = $this->makeBooking($token);

        $this->withToken($token)->postJson("/api/v1/bookings/{$booking['id']}/cancel", [
            'reason' => 'Change of plans',
        ])->assertOk()->assertJsonPath('booking.status', 'cancelled');
    }

    public function test_cancelling_past_the_deadline_is_refused(): void
    {
        $token = $this->signIn();
        $booking = $this->makeBooking($token);

        // Deadline is 4 hours; move the appointment to 1 hour away.
        Booking::query()->withoutTenancy()->whereKey($booking['id'])->update([
            'starts_at' => CarbonImmutable::now()->addHour(),
            'ends_at' => CarbonImmutable::now()->addHours(3),
        ]);

        $this->withToken($token)->postJson("/api/v1/bookings/{$booking['id']}/cancel")
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'CANCELLATION_DEADLINE_PASSED');
    }

    public function test_a_customer_cannot_touch_another_customers_booking(): void
    {
        $ownerToken = $this->signIn('0512345678');
        $booking = $this->makeBooking($ownerToken);

        $intruderToken = $this->signIn('0587654321');
        $this->app['auth']->forgetGuards();

        $this->withToken($intruderToken)->getJson("/api/v1/bookings/{$booking['id']}")
            ->assertStatus(404);

        $this->app['auth']->forgetGuards();

        $this->withToken($intruderToken)->postJson("/api/v1/bookings/{$booking['id']}/cancel")
            ->assertStatus(404);
    }

    // =====================================================================
    // My Stores — and the absence of a marketplace (spec §5, §46)
    // =====================================================================

    public function test_my_stores_is_empty_before_any_scan(): void
    {
        $token = $this->signIn();

        $this->withToken($token)->getJson('/api/v1/me/stores')
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }

    public function test_adding_a_store_by_code_puts_it_on_the_home_screen(): void
    {
        $token = $this->signIn();

        $this->withToken($token)->postJson('/api/v1/me/stores', [
            'token' => $this->glow->public_token,
        ])->assertCreated()->assertJsonPath('newly_added', true);

        $this->withToken($token)->getJson('/api/v1/me/stores')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.token', $this->glow->public_token);
    }

    public function test_adding_the_same_store_twice_does_not_duplicate_it(): void
    {
        $token = $this->signIn();

        $this->withToken($token)->postJson('/api/v1/me/stores', ['token' => $this->glow->public_token]);
        $this->withToken($token)->postJson('/api/v1/me/stores', ['token' => $this->glow->public_token])
            ->assertOk()
            ->assertJsonPath('newly_added', false);

        $this->assertSame(1, CustomerStore::count());
    }

    public function test_removing_a_store_hides_it_without_losing_history(): void
    {
        $token = $this->signIn();
        $this->withToken($token)->postJson('/api/v1/me/stores', ['token' => $this->glow->public_token]);

        $this->withToken($token)->deleteJson("/api/v1/me/stores/{$this->glow->public_token}")->assertOk();

        $this->withToken($token)->getJson('/api/v1/me/stores')->assertJsonCount(0, 'data');

        // The link still exists — it is hidden, not deleted.
        $this->assertSame(1, CustomerStore::count());
    }

    /**
     * ====================================================================
     * THE PRODUCT RULE, ENFORCED (spec §46)
     *
     * A customer must never see a store they did not personally add. There is
     * no discovery endpoint, and My Stores never leaks one.
     * ====================================================================
     */
    public function test_a_customer_never_sees_a_store_they_did_not_add(): void
    {
        // A second, entirely unrelated business exists on the platform.
        $other = Merchant::factory()->create(['display_name' => 'Someone Else Spa']);
        app(TenantContext::class)->setTenant($other);
        Store::factory()->create(['merchant_id' => $other->id, 'name_en' => 'Someone Else Spa']);
        app(TenantContext::class)->setTenant(null);

        $token = $this->signIn();
        $this->withToken($token)->postJson('/api/v1/me/stores', ['token' => $this->glow->public_token]);

        $response = $this->withToken($token)->getJson('/api/v1/me/stores');

        $response->assertOk()->assertJsonCount(1, 'data');
        $response->assertDontSee('Someone Else Spa');
    }

    public function test_no_marketplace_discovery_endpoints_exist(): void
    {
        $token = $this->signIn();

        // Every one of these would turn Wasla into a marketplace (§40, §46).
        foreach ([
            '/api/v1/stores',
            '/api/v1/search',
            '/api/v1/stores/search',
            '/api/v1/nearby',
            '/api/v1/categories',
            '/api/v1/merchants',
        ] as $forbidden) {
            $this->withToken($token)->getJson($forbidden)->assertStatus(404);
        }
    }

    // =====================================================================
    // Deferred deep linking (spec §7)
    // =====================================================================

    public function test_a_deep_link_survives_the_app_store_round_trip(): void
    {
        // 1. Landing page records the fingerprint before sending the user away.
        $this->withHeaders(['User-Agent' => 'iPhone', 'Accept-Language' => 'ar'])
            ->postJson('/api/v1/deep-link/record', [
                'token' => $this->glow->public_token,
                'platform' => 'ios',
                'screen' => '390x844',
            ])->assertCreated();

        // 2. App claims it on first launch from the same device.
        $this->withHeaders(['User-Agent' => 'iPhone', 'Accept-Language' => 'ar'])
            ->postJson('/api/v1/deep-link/claim', ['platform' => 'ios', 'screen' => '390x844'])
            ->assertOk()
            ->assertJsonPath('token', $this->glow->public_token)
            ->assertJsonPath('matched_by', 'fingerprint');
    }

    public function test_a_launch_with_no_pending_link_is_not_an_error(): void
    {
        // Most launches are ordinary. The app just shows its home screen.
        $this->postJson('/api/v1/deep-link/claim', ['platform' => 'ios'])
            ->assertOk()
            ->assertJsonPath('token', null);
    }

    public function test_android_uses_the_exact_install_referrer(): void
    {
        $this->postJson('/api/v1/deep-link/claim', [
            'platform' => 'android',
            'install_referrer' => 'utm_source=wasla&store='.$this->glow->public_token,
        ])
            ->assertOk()
            ->assertJsonPath('token', $this->glow->public_token)
            ->assertJsonPath('matched_by', 'install_referrer');
    }

    /**
     * @return array<string, mixed>
     */
    private function makeBooking(string $token): array
    {
        $date = CarbonImmutable::now('Asia/Riyadh')->addDays(3)->format('Y-m-d');

        $slot = $this->getJson(
            "/api/v1/stores/{$this->glow->public_token}/availability?service_id={$this->hairColor->id}&date={$date}"
        )->json('days.0.slots.0');

        return $this->withToken($token)->postJson('/api/v1/bookings', [
            'store_token' => $this->glow->public_token,
            'service_id' => $this->hairColor->id,
            'starts_at' => $slot['starts_at'],
            'staff_id' => $slot['staff_id'],
        ])->json();
    }
}
