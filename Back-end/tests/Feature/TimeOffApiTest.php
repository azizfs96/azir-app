<?php

namespace Tests\Feature;

use App\Domain\Booking\BookingService;
use App\Models\BookingSettings;
use App\Models\Branch;
use App\Models\Merchant;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use App\Models\TimeOff;
use App\Models\User;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * BLOCKED TIME API — the audit's #1 missing feature, now with a door.
 *
 * The scenario that motivated it: a stylist works 16:00-23:00 and needs
 * 18:00-19:00 off TODAY ONLY — an errand, not a weekly break. The engine has
 * honoured time_off rows all along; these tests pin the new API and the
 * end-to-end effect: the hour vanishes from availability for that date only,
 * the write path refuses it, and existing bookings inside the window are
 * REPORTED, never cancelled.
 * ============================================================================
 */
class TimeOffApiTest extends TestCase
{
    use RefreshDatabase;

    private const TZ = 'Asia/Riyadh';

    private Merchant $merchant;

    private Store $store;

    private Branch $branch;

    private Staff $sara;

    private Service $haircut;

    private User $owner;

    protected function setUp(): void
    {
        parent::setUp();

        $this->merchant = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($this->merchant);

        $this->store = Store::factory()->create(['merchant_id' => $this->merchant->id]);

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $this->store->id,
            'min_lead_time_minutes' => 0,
            'max_advance_days' => 365,
            'staff_selection' => true,
        ]));

        $this->branch = Branch::factory()->forStore($this->store)->create([
            'slot_interval_minutes' => 30,
            'buffer_before_minutes' => 0,
            'buffer_after_minutes' => 0,
        ]);

        $this->sara = Staff::factory()->forStore($this->store)->create([
            'name' => 'Sara', 'branch_id' => $this->branch->id,
        ]);

        // The user's exact shape: an evening shift 16:00-23:00, every day.
        foreach (range(0, 6) as $day) {
            $this->branch->schedules()->create([
                'day_of_week' => $day, 'opens_at' => '16:00', 'closes_at' => '23:00',
            ]);
            $this->sara->schedules()->create([
                'day_of_week' => $day, 'starts_at' => '16:00', 'ends_at' => '23:00',
            ]);
        }

        $this->haircut = Service::factory()->forStore($this->store)->create([
            'duration_minutes' => 30, 'buffer_after_minutes' => 0, 'price' => 100,
        ]);

        $this->owner = User::factory()->create([
            'role' => 'merchant_owner', 'merchant_id' => $this->merchant->id,
        ]);

        app(TenantContext::class)->setTenant(null);
    }

    private function asOwner(): static
    {
        $this->actingAs($this->owner);
        app(TenantContext::class)->setTenant($this->merchant);

        return $this;
    }

    private function date(int $daysAhead = 3): string
    {
        return CarbonImmutable::now(self::TZ)->addDays($daysAhead)->format('Y-m-d');
    }

    /** @return array<int, string> */
    private function publicSlots(string $date): array
    {
        app(TenantContext::class)->setTenant(null);
        $this->app->forgetInstance(TenantContext::class);

        return collect(
            $this->getJson(
                "/api/v1/stores/{$this->store->public_token}/availability"
                    ."?service_id={$this->haircut->id}&date={$date}&staff_id={$this->sara->id}",
            )->assertOk()->json('days.0.slots'),
        )->pluck('time')->all();
    }

    // ---- the exact scenario ------------------------------------------------

    public function test_blocking_six_to_seven_hides_exactly_that_hour_on_that_date_only(): void
    {
        $date = $this->date();

        $before = $this->publicSlots($date);
        $this->assertContains('18:00', $before, 'Fixture: 18:00 should start out free.');

        $this->asOwner()->postJson('/api/v1/merchant/time-off', [
            'staff_id' => $this->sara->id,
            'date' => $date,
            'from' => '18:00',
            'to' => '19:00',
            'reason' => 'ظرف طارئ',
        ])->assertCreated();

        $after = $this->publicSlots($date);

        // 18:00 and 18:30 gone; the shift edges survive. 17:30 survives because
        // the 30-minute cut ends exactly at 18:00 (half-open intervals).
        $this->assertNotContains('18:00', $after);
        $this->assertNotContains('18:30', $after);
        $this->assertContains('17:30', $after);
        $this->assertContains('19:00', $after);
        $this->assertContains('16:00', $after);

        // TOMORROW is untouched — this is a date block, not a weekly break.
        $tomorrow = $this->publicSlots($this->date(4));
        $this->assertContains('18:00', $tomorrow, 'The block leaked to other days.');
    }

    public function test_the_write_path_refuses_the_blocked_hour(): void
    {
        $date = $this->date();

        $this->asOwner()->postJson('/api/v1/merchant/time-off', [
            'staff_id' => $this->sara->id,
            'date' => $date, 'from' => '18:00', 'to' => '19:00',
        ])->assertCreated();

        app(TenantContext::class)->setTenant(null);

        $this->expectException(\App\Domain\Booking\Exceptions\SlotNoLongerAvailable::class);

        app(BookingService::class)->create(
            store: Store::withoutGlobalScopes()->with('bookingSettings')->find($this->store->id),
            service: $this->haircut,
            startsAt: CarbonImmutable::parse("{$date} 18:00", self::TZ),
            branch: $this->branch,
            requestedStaff: Staff::withoutGlobalScopes()->with(['schedules', 'services'])->find($this->sara->id),
        );
    }

    public function test_deleting_the_block_reopens_the_hour(): void
    {
        $date = $this->date();

        $created = $this->asOwner()->postJson('/api/v1/merchant/time-off', [
            'staff_id' => $this->sara->id,
            'date' => $date, 'from' => '18:00', 'to' => '19:00',
        ])->assertCreated()->json('data');

        $this->assertNotContains('18:00', $this->publicSlots($date));

        $this->asOwner()->deleteJson("/api/v1/merchant/time-off/{$created['id']}")->assertOk();

        $this->assertContains('18:00', $this->publicSlots($date), 'Deleting the block did not reopen the hour.');
    }

    // ---- affected bookings -------------------------------------------------

    public function test_existing_bookings_inside_the_window_are_reported_not_cancelled(): void
    {
        $date = $this->date();

        app(TenantContext::class)->setTenant(null);

        $booking = app(BookingService::class)->create(
            store: Store::withoutGlobalScopes()->with('bookingSettings')->find($this->store->id),
            service: $this->haircut,
            startsAt: CarbonImmutable::parse("{$date} 18:00", self::TZ),
            branch: $this->branch,
            requestedStaff: Staff::withoutGlobalScopes()->with(['schedules', 'services'])->find($this->sara->id),
        );

        $response = $this->asOwner()->postJson('/api/v1/merchant/time-off', [
            'staff_id' => $this->sara->id,
            'date' => $date, 'from' => '18:00', 'to' => '19:00',
        ])->assertCreated()->json();

        $this->assertCount(1, $response['affected_bookings']);
        $this->assertSame($booking->reference, $response['affected_bookings'][0]['reference']);

        // The booking itself is untouched — cancelling is the merchant's call.
        $this->assertSame('confirmed', $booking->fresh()->booking_status->value);
    }

    // ---- validation and isolation ------------------------------------------

    public function test_exactly_one_target_is_required(): void
    {
        $this->asOwner()->postJson('/api/v1/merchant/time-off', [
            'date' => $this->date(), 'from' => '18:00', 'to' => '19:00',
        ])->assertStatus(422)->assertJsonPath('error_code', 'TIME_OFF_TARGET_INVALID');

        $this->asOwner()->postJson('/api/v1/merchant/time-off', [
            'staff_id' => $this->sara->id,
            'branch_id' => $this->branch->id,
            'date' => $this->date(), 'from' => '18:00', 'to' => '19:00',
        ])->assertStatus(422)->assertJsonPath('error_code', 'TIME_OFF_TARGET_INVALID');
    }

    public function test_a_block_entirely_in_the_past_is_refused(): void
    {
        $this->asOwner()->postJson('/api/v1/merchant/time-off', [
            'staff_id' => $this->sara->id,
            'date' => CarbonImmutable::now(self::TZ)->subDays(2)->format('Y-m-d'),
            'from' => '18:00', 'to' => '19:00',
        ])->assertStatus(422)->assertJsonPath('error_code', 'TIME_OFF_IN_PAST');
    }

    public function test_another_merchants_staff_reads_as_not_found(): void
    {
        $other = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($other);
        $otherStore = Store::factory()->create(['merchant_id' => $other->id]);
        $otherStaff = Staff::factory()->forStore($otherStore)->create(['name' => 'Foreign']);
        app(TenantContext::class)->setTenant(null);

        $this->asOwner()->postJson('/api/v1/merchant/time-off', [
            'staff_id' => $otherStaff->id,
            'date' => $this->date(), 'from' => '18:00', 'to' => '19:00',
        ])->assertNotFound();

        // And their rows are invisible to us end to end.
        app(TenantContext::class)->setTenant($other);
        $foreign = TimeOff::create([
            'staff_id' => $otherStaff->id,
            'starts_at' => CarbonImmutable::now()->addDay(),
            'ends_at' => CarbonImmutable::now()->addDays(2),
        ]);
        app(TenantContext::class)->setTenant(null);

        $this->asOwner()->deleteJson("/api/v1/merchant/time-off/{$foreign->id}")->assertNotFound();
    }

    public function test_midnight_to_midnight_blocks_the_whole_day(): void
    {
        $date = $this->date();

        $this->asOwner()->postJson('/api/v1/merchant/time-off', [
            'staff_id' => $this->sara->id,
            'date' => $date, 'from' => '00:00', 'to' => '00:00',
        ])->assertCreated();

        $this->assertSame([], $this->publicSlots($date), 'A full-day block left slots behind.');
        $this->assertNotSame([], $this->publicSlots($this->date(4)), 'The full-day block leaked.');
    }
}
