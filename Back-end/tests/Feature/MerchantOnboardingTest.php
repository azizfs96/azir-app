<?php

namespace Tests\Feature;

use App\Models\Booking;
use App\Models\Merchant;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * MERCHANT SETUP (spec §11, §42)
 *
 *   Register -> Beauty & Wellness -> Branch -> Services -> [Staff]
 *            -> Booking settings -> Generate QR -> Go live
 *
 * The §41 principle under test: "The merchant should be able to create their
 * digital booking experience without technical knowledge."
 * ============================================================================
 */
class MerchantOnboardingTest extends TestCase
{
    use RefreshDatabase;

    /**
     * @return array{token: string, merchant: Merchant}
     */
    private function register(string $email = 'owner@glow.sa'): array
    {
        $this->app['auth']->forgetGuards();

        $response = $this->postJson('/api/v1/auth/merchant/register', [
            'business_name' => 'Glow Beauty',
            'owner_name' => 'Abdulaziz',
            'email' => $email,
            'phone' => '0501110001',
            'password' => 'secret-password',
        ])->assertCreated();

        return [
            'token' => $response->json('token'),
            'merchant' => Merchant::where('contact_email', $email)->firstOrFail(),
        ];
    }

    /** Approve, as an admin would (spec §39). */
    private function approve(Merchant $merchant): void
    {
        $merchant->forceFill([
            'status' => Merchant::STATUS_APPROVED,
            'approved_at' => now(),
        ])->save();
    }

    // =====================================================================
    // Registration
    // =====================================================================

    public function test_registering_creates_a_working_but_unpublished_store(): void
    {
        ['merchant' => $merchant] = $this->register();

        $this->assertSame(Merchant::STATUS_PENDING, $merchant->status);

        $store = $merchant->store;
        $this->assertNotNull($store, 'Registration should create the store immediately');
        $this->assertFalse((bool) $store->is_published);

        // Booking settings and a QR exist from minute one, so the merchant
        // never has to think about them (spec §11).
        $this->assertNotNull($store->bookingSettings);
        $this->assertNotNull($store->qrCode);
        $this->assertSame(8, strlen($store->public_token));
    }

    public function test_the_owner_is_signed_in_immediately_after_registering(): void
    {
        ['token' => $token] = $this->register();

        $this->withToken($token)->getJson('/api/v1/auth/me')
            ->assertOk()
            ->assertJsonPath('data.role', 'merchant_owner');
    }

    public function test_a_duplicate_email_is_rejected(): void
    {
        $this->register();
        $this->app['auth']->forgetGuards();

        $this->postJson('/api/v1/auth/merchant/register', [
            'business_name' => 'Copycat',
            'owner_name' => 'Someone',
            'email' => 'owner@glow.sa',
            'phone' => '0509998888',
            'password' => 'secret-password',
        ])->assertStatus(422);
    }

    public function test_an_invalid_saudi_number_is_rejected(): void
    {
        $this->postJson('/api/v1/auth/merchant/register', [
            'business_name' => 'Glow',
            'owner_name' => 'A',
            'email' => 'x@glow.sa',
            'phone' => '0401234567',
            'password' => 'secret-password',
        ])->assertStatus(422)->assertJsonPath('error_code', 'VALIDATION_FAILED');
    }

    // =====================================================================
    // A pending merchant can finish setup but not operate
    // =====================================================================

    public function test_a_pending_merchant_can_still_reach_onboarding(): void
    {
        ['token' => $token] = $this->register();

        $this->withToken($token)->getJson('/api/v1/merchant/onboarding')
            ->assertOk()
            ->assertJsonPath('status', 'pending')
            ->assertJsonPath('progress.has_qr', true);
    }

    public function test_a_pending_merchant_cannot_reach_the_dashboard(): void
    {
        ['token' => $token] = $this->register();

        $this->withToken($token)->getJson('/api/v1/merchant/dashboard')
            ->assertStatus(403)
            ->assertJsonPath('error_code', 'MERCHANT_NOT_ACTIVE');
    }

    public function test_a_suspended_merchant_loses_access(): void
    {
        ['token' => $token, 'merchant' => $merchant] = $this->register();
        $this->approve($merchant);
        $merchant->forceFill(['status' => Merchant::STATUS_SUSPENDED])->save();

        $this->withToken($token)->getJson('/api/v1/merchant/dashboard')
            ->assertStatus(403)
            ->assertJsonPath('error_code', 'MERCHANT_NOT_ACTIVE');
    }

    // =====================================================================
    // The §42 worked example, end to end
    // =====================================================================

    public function test_a_salon_owner_can_go_from_registration_to_a_live_qr(): void
    {
        ['token' => $token, 'merchant' => $merchant] = $this->register();
        $this->approve($merchant);

        $api = fn () => $this->withToken($token);

        // Step 3 — branch.
        $branchId = $api()->postJson('/api/v1/merchant/branches', [
            'name_ar' => 'العليا',
            'name_en' => 'Olaya',
            'city' => 'Riyadh',
        ])->assertCreated()->json('id');

        $api()->putJson("/api/v1/merchant/branches/{$branchId}/schedule", [
            'schedule' => collect(range(0, 6))->map(fn ($day) => [
                'day_of_week' => $day, 'opens_at' => '10:00', 'closes_at' => '22:00',
            ])->all(),
        ])->assertOk();

        // Step 4 — the three services from §42.
        foreach ([
            ['قص شعر', 'Hair Cut', 100, 30],
            ['صبغة شعر', 'Hair Color', 250, 120],
            ['تنظيف بشرة', 'Facial', 180, 60],
        ] as [$ar, $en, $price, $minutes]) {
            $api()->postJson('/api/v1/merchant/services', [
                'name_ar' => $ar, 'name_en' => $en,
                'price' => $price, 'duration_minutes' => $minutes,
            ])->assertCreated();
        }

        // Step 5 — staff (optional, but §42 adds two).
        foreach (['Sara', 'Reem'] as $name) {
            $staffId = $api()->postJson('/api/v1/merchant/staff', [
                'name' => $name, 'branch_id' => $branchId,
            ])->assertCreated()->json('id');

            $api()->putJson("/api/v1/merchant/staff/{$staffId}/schedule", [
                'schedule' => collect(range(0, 6))->map(fn ($day) => [
                    'day_of_week' => $day, 'starts_at' => '10:00', 'ends_at' => '22:00',
                ])->all(),
            ])->assertOk();
        }

        // Step 6 — booking settings: customer selects staff = YES.
        $api()->patchJson('/api/v1/merchant/settings/booking', [
            'staff_selection' => true,
            'allow_cancellation' => true,
            'allow_rescheduling' => true,
        ])->assertOk();

        // Step 8 — the QR already exists.
        $qr = $api()->getJson('/api/v1/merchant/qr')->assertOk();
        $qr->assertJsonPath('analytics.total_scans', 0);
        $this->assertStringContainsString('/s/', $qr->json('deep_link'));

        // Step 9 — go live.
        $api()->postJson('/api/v1/merchant/onboarding/publish')
            ->assertOk()
            ->assertJsonPath('awaiting_approval', false);

        // THE PAYOFF: the QR now resolves for a customer, with the merchant's
        // own configuration driving the flow — no code was written for them.
        $token8 = $merchant->store->fresh()->public_token;

        $storefront = $this->getJson("/api/v1/stores/{$token8}")->assertOk();

        $storefront->assertJsonPath('configuration.staff_selection', true);
        $this->assertContains('staff', $storefront->json('flow.*.step'));
        $this->assertCount(3, $storefront->json('services'));
        $this->assertCount(2, $storefront->json('staff'));
    }

    public function test_publishing_is_refused_until_the_essentials_exist(): void
    {
        ['token' => $token, 'merchant' => $merchant] = $this->register();
        $this->approve($merchant);

        $this->withToken($token)->postJson('/api/v1/merchant/onboarding/publish')
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'ONBOARDING_INCOMPLETE')
            ->assertJsonPath('blockers', ['branch_required', 'service_required']);
    }

    // =====================================================================
    // Tenant isolation across the CRUD surface (spec §26)
    // =====================================================================

    public function test_a_merchant_only_sees_their_own_catalogue(): void
    {
        ['token' => $tokenA, 'merchant' => $merchantA] = $this->register('a@glow.sa');
        $this->approve($merchantA);

        $this->withToken($tokenA)->postJson('/api/v1/merchant/services', [
            'name_ar' => 'خدمة أ', 'price' => 100, 'duration_minutes' => 30,
        ])->assertCreated();

        // A second, unrelated business.
        $merchantB = Merchant::factory()->create();
        app(TenantContext::class)->setTenant($merchantB);
        $storeB = Store::factory()->create(['merchant_id' => $merchantB->id]);
        $serviceB = Service::factory()->forStore($storeB)->create(['name_ar' => 'خدمة ب']);
        app(TenantContext::class)->setTenant(null);

        $response = $this->withToken($tokenA)->getJson('/api/v1/merchant/services')->assertOk();

        $this->assertCount(1, $response->json('data'));
        $response->assertDontSee('خدمة ب');
    }

    public function test_a_merchant_cannot_edit_another_merchants_service(): void
    {
        ['token' => $tokenA, 'merchant' => $merchantA] = $this->register('a@glow.sa');
        $this->approve($merchantA);

        $merchantB = Merchant::factory()->create();
        app(TenantContext::class)->setTenant($merchantB);
        $storeB = Store::factory()->create(['merchant_id' => $merchantB->id]);
        $serviceB = Service::factory()->forStore($storeB)->create(['price' => 500]);
        app(TenantContext::class)->setTenant(null);

        // 404, never 403 — a 403 would confirm the row exists (§4).
        $this->withToken($tokenA)
            ->putJson("/api/v1/merchant/services/{$serviceB->id}", ['price' => 1])
            ->assertStatus(404);

        $this->assertSame('500.00', $serviceB->fresh()->price);
    }

    // =====================================================================
    // Dashboard and booking management (spec §13, §19)
    // =====================================================================

    public function test_the_dashboard_reports_today(): void
    {
        ['token' => $token, 'merchant' => $merchant] = $this->register();
        $this->approve($merchant);

        $this->withToken($token)->getJson('/api/v1/merchant/dashboard')
            ->assertOk()
            ->assertJsonStructure([
                'date', 'timezone',
                'today' => ['total', 'confirmed', 'completed', 'cancelled', 'no_show'],
                'revenue' => ['amount', 'currency'],
                'upcoming',
            ]);
    }

    public function test_a_merchant_can_walk_a_booking_through_the_state_machine(): void
    {
        ['token' => $token, 'merchant' => $merchant] = $this->register();
        $this->approve($merchant);

        $booking = $this->seedBookingFor($merchant);
        $api = fn () => $this->withToken($token);

        $api()->postJson("/api/v1/merchant/bookings/{$booking->id}/status", ['status' => 'checked_in'])
            ->assertOk()->assertJsonPath('status', 'checked_in');

        $api()->postJson("/api/v1/merchant/bookings/{$booking->id}/status", ['status' => 'completed'])
            ->assertOk()->assertJsonPath('status', 'completed');

        // Terminal — the state machine refuses anything further (§19).
        $api()->postJson("/api/v1/merchant/bookings/{$booking->id}/status", ['status' => 'cancelled'])
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'INVALID_STATUS_TRANSITION');
    }

    public function test_the_settings_endpoint_refuses_online_payment_while_it_is_unavailable(): void
    {
        ['token' => $token, 'merchant' => $merchant] = $this->register();
        $this->approve($merchant);

        // Payments are descoped for the MVP, so a merchant must not be able to
        // configure a checkout that does not exist.
        $this->withToken($token)->patchJson('/api/v1/merchant/settings/booking', [
            'payment_required' => true,
        ])
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'ONLINE_PAYMENT_UNAVAILABLE');
    }

    public function test_the_last_branch_cannot_be_deleted(): void
    {
        ['token' => $token, 'merchant' => $merchant] = $this->register();
        $this->approve($merchant);

        $branchId = $this->withToken($token)->postJson('/api/v1/merchant/branches', [
            'name_ar' => 'العليا',
        ])->json('id');

        $this->withToken($token)->deleteJson("/api/v1/merchant/branches/{$branchId}")
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'LAST_BRANCH');
    }

    public function test_regenerating_the_qr_issues_a_new_token(): void
    {
        ['token' => $token, 'merchant' => $merchant] = $this->register();
        $this->approve($merchant);

        $before = $merchant->store->public_token;

        $after = $this->withToken($token)->postJson('/api/v1/merchant/qr/regenerate')
            ->assertOk()->json('token');

        $this->assertNotSame($before, $after);

        // The old printed code must stop resolving — that is the point (§24).
        $this->getJson("/api/v1/stores/{$before}")->assertStatus(404);
    }

    private function seedBookingFor(Merchant $merchant): Booking
    {
        app(TenantContext::class)->setTenant($merchant);

        $store = $merchant->store;
        $branch = \App\Models\Branch::factory()->forStore($store)->create();
        $service = Service::factory()->forStore($store)->create(['duration_minutes' => 30]);
        $staff = Staff::factory()->forStore($store)->create(['branch_id' => $branch->id]);

        $booking = new Booking([
            'store_id' => $store->id,
            'branch_id' => $branch->id,
            'service_id' => $service->id,
            'staff_id' => $staff->id,
            'starts_at' => now()->addDay(),
            'ends_at' => now()->addDay()->addMinutes(30),
            'duration_minutes' => 30,
            'price' => 100,
        ]);
        $booking->forceFill(['merchant_id' => $merchant->id])->save();
        $booking->transitionTo(\App\Domain\Booking\BookingStatus::Confirmed, 'system');

        app(TenantContext::class)->setTenant(null);

        return $booking;
    }
}
