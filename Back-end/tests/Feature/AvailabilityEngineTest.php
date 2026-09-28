<?php

namespace Tests\Feature;

use App\Domain\Booking\BookingStatus;
use App\Domain\Scheduling\AvailabilityEngine;
use App\Domain\Scheduling\Slot;
use App\Models\Booking;
use App\Models\BookingSettings;
use App\Models\Branch;
use App\Models\Merchant;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The availability engine (spec §17 — "This is critical").
 *
 * The centrepiece is test_the_spec_section_17_worked_example, which encodes the
 * exact scenario from the brief. If that ever fails, the engine is wrong.
 */
class AvailabilityEngineTest extends TestCase
{
    use RefreshDatabase;

    private const TZ = 'Asia/Riyadh';

    private Store $store;

    private Branch $branch;

    private Staff $sara;

    private Service $hairColor;

    private AvailabilityEngine $engine;

    protected function setUp(): void
    {
        parent::setUp();

        $merchant = Merchant::factory()->create();
        app(TenantContext::class)->setTenant($merchant);

        $this->store = Store::factory()->create(['merchant_id' => $merchant->id]);

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $this->store->id,
            // Neutralised so the worked example is not filtered by policy.
            'min_lead_time_minutes' => 0,
            'max_advance_days' => 365,
        ]));

        $this->branch = Branch::factory()->forStore($this->store)->create([
            'slot_interval_minutes' => 15,
            'buffer_before_minutes' => 0,
            'buffer_after_minutes' => 0,
        ]);

        // Branch open 10:00-22:00 every day.
        foreach (range(0, 6) as $day) {
            $this->branch->schedules()->create([
                'day_of_week' => $day,
                'opens_at' => '10:00',
                'closes_at' => '22:00',
            ]);
        }

        $this->sara = Staff::factory()->forStore($this->store)->create([
            'name' => 'Sara',
            'branch_id' => $this->branch->id,
        ]);

        // Sara works 10:00-22:00 with a 14:00-15:00 break.
        foreach (range(0, 6) as $day) {
            $this->sara->schedules()->create([
                'day_of_week' => $day,
                'starts_at' => '10:00',
                'ends_at' => '22:00',
                'break_starts_at' => '14:00',
                'break_ends_at' => '15:00',
            ]);
        }

        $this->hairColor = Service::factory()->forStore($this->store)->create([
            'name_en' => 'Hair Color',
            'duration_minutes' => 120,
            'buffer_after_minutes' => 0,
            'price' => 250,
        ]);

        $this->engine = app(AvailabilityEngine::class);
    }

    private function date(string $ymd): CarbonImmutable
    {
        return CarbonImmutable::parse($ymd, self::TZ);
    }

    /*
     * Reload helpers. Lazy loading is disabled outside production (see
     * AppServiceProvider) precisely so N+1s in this engine surface as failures,
     * so every model handed to it must arrive with its relations loaded.
     */

    private function store(): Store
    {
        return Store::with('bookingSettings')->findOrFail($this->store->id);
    }

    private function branch(): Branch
    {
        return Branch::with('schedules')->findOrFail($this->branch->id);
    }

    private function sara(): Staff
    {
        return $this->staffById($this->sara->id);
    }

    private function staffById(int $id): Staff
    {
        return Staff::with(['schedules', 'services'])->findOrFail($id);
    }

    /**
     * @return array<int, string> local HH:MM start times
     */
    private function times(CarbonImmutable $date, ?Staff $staff = null): array
    {
        return $this->engine
            ->slotsFor(
                $this->store(),
                $this->hairColor,
                $date,
                $this->branch(),
                $staff,
                // Fix "now" well before the test date so lead time never bites.
                $this->date('2026-09-01')->setTime(0, 0),
            )
            ->map(fn (Slot $slot) => $slot->startsAt->setTimezone(self::TZ)->format('H:i'))
            ->all();
    }

    // =====================================================================
    // THE SPEC §17 WORKED EXAMPLE
    // =====================================================================

    /**
     * From the brief:
     *
     *   Service: Hair Color, duration 120 minutes.
     *   If a staff member already has 18:00-20:00, the system must not offer
     *   overlapping slots.
     *
     * Sara: works 10:00-22:00, break 14:00-15:00, booked 18:00-20:00.
     * Free windows are therefore 10:00-14:00, 15:00-18:00, 20:00-22:00, and a
     * 120-minute service fits only where a full two hours remain.
     */
    public function test_the_spec_section_17_worked_example(): void
    {
        $date = $this->date('2026-09-15');

        Booking::create([
            'store_id' => $this->store->id,
            'branch_id' => $this->branch->id,
            'service_id' => $this->hairColor->id,
            'staff_id' => $this->sara->id,
            'starts_at' => $date->setTime(18, 0)->utc(),
            'ends_at' => $date->setTime(20, 0)->utc(),
            'duration_minutes' => 120,
            'price' => 250,
        ])->transitionTo(BookingStatus::Confirmed);

        $times = $this->times($date, $this->sara);

        $expected = [
            // 10:00-14:00 window — last start that still fits 120 min is 12:00.
            '10:00', '10:15', '10:30', '10:45',
            '11:00', '11:15', '11:30', '11:45',
            '12:00',
            // 15:00-18:00 window — last fitting start is 16:00.
            '15:00', '15:15', '15:30', '15:45',
            '16:00',
            // 20:00-22:00 window — exactly one fit.
            '20:00',
        ];

        $this->assertSame($expected, $times);

        // The brief calls this one out explicitly: 17:00 would run to 19:00 and
        // collide with the 18:00 booking.
        $this->assertNotContains('17:00', $times);

        // And nothing may be offered during the break.
        $this->assertNotContains('14:00', $times);
    }

    // =====================================================================
    // Individual constraints
    // =====================================================================

    public function test_a_cancelled_booking_releases_its_slot(): void
    {
        $date = $this->date('2026-09-16');

        $booking = Booking::create([
            'store_id' => $this->store->id,
            'branch_id' => $this->branch->id,
            'service_id' => $this->hairColor->id,
            'staff_id' => $this->sara->id,
            'starts_at' => $date->setTime(10, 0)->utc(),
            'ends_at' => $date->setTime(12, 0)->utc(),
            'duration_minutes' => 120,
            'price' => 250,
        ]);
        $booking->transitionTo(BookingStatus::Confirmed);

        $this->assertNotContains('10:00', $this->times($date, $this->sara));

        $booking->transitionTo(BookingStatus::Cancelled, 'customer');

        $this->assertContains('10:00', $this->times($date, $this->sara));
    }

    public function test_time_off_removes_the_whole_day(): void
    {
        $date = $this->date('2026-09-17');

        $this->sara->timeOff()->create([
            'starts_at' => $date->startOfDay()->utc(),
            'ends_at' => $date->endOfDay()->utc(),
            'reason' => 'Annual leave',
        ]);

        $this->assertSame([], $this->times($date, $this->sara));
    }

    public function test_a_day_the_staff_member_is_off_yields_nothing(): void
    {
        $date = $this->date('2026-09-18'); // Friday

        $this->sara->schedules()->where('day_of_week', $date->dayOfWeek)->update(['is_off' => true]);

        $this->assertSame([], $this->times($date->setTimezone(self::TZ), $this->sara()));
    }

    public function test_buffer_time_widens_an_existing_booking(): void
    {
        $date = $this->date('2026-09-19');
        $this->branch->update(['buffer_after_minutes' => 30]);

        Booking::create([
            'store_id' => $this->store->id,
            'branch_id' => $this->branch->id,
            'service_id' => $this->hairColor->id,
            'staff_id' => $this->sara->id,
            'starts_at' => $date->setTime(10, 0)->utc(),
            'ends_at' => $date->setTime(12, 0)->utc(),
            'duration_minutes' => 120,
            'price' => 250,
        ])->transitionTo(BookingStatus::Confirmed);

        $times = $this->times($date, $this->sara());

        // Booking ends 12:00 but the 30-minute buffer pushes the next start to
        // 12:30 — and 12:30 + 120 = 14:30 overruns the 14:00 break, so the next
        // real opportunity is after the break.
        $this->assertNotContains('12:00', $times);
        $this->assertNotContains('12:30', $times);
        $this->assertContains('15:00', $times);
    }

    public function test_minimum_lead_time_hides_imminent_slots(): void
    {
        $date = $this->date('2026-09-20');
        $this->store->bookingSettings->update(['min_lead_time_minutes' => 180]);

        $slots = $this->engine->slotsFor(
            $this->store(),
            $this->hairColor,
            $date,
            $this->branch(),
            $this->sara(),
            $date->setTime(10, 0), // "now" is 10:00 on the day itself
        );

        $first = $slots->first();

        $this->assertNotNull($first);
        $this->assertGreaterThanOrEqual(
            $date->setTime(13, 0)->utc()->getTimestamp(),
            $first->startsAt->getTimestamp(),
            'A slot inside the 3-hour lead time was offered.'
        );
    }

    public function test_dates_beyond_the_advance_window_are_empty(): void
    {
        $this->store->bookingSettings->update(['max_advance_days' => 7]);

        $slots = $this->engine->slotsFor(
            $this->store(),
            $this->hairColor,
            $this->date('2026-10-30'),
            $this->branch(),
            $this->sara(),
            $this->date('2026-09-01'),
        );

        $this->assertTrue($slots->isEmpty());
    }

    public function test_split_shifts_are_respected(): void
    {
        // Prayer-time closure: branch open 10:00-14:00 then 16:00-22:00.
        $date = $this->date('2026-09-21');
        $this->branch->schedules()->where('day_of_week', $date->dayOfWeek)->delete();
        $this->branch->schedules()->create([
            'day_of_week' => $date->dayOfWeek, 'opens_at' => '10:00', 'closes_at' => '14:00',
        ]);
        $this->branch->schedules()->create([
            'day_of_week' => $date->dayOfWeek, 'opens_at' => '16:00', 'closes_at' => '22:00',
        ]);

        $times = $this->times($date, $this->sara());

        // Nothing may start where it would run through the 14:00-16:00 closure.
        $this->assertNotContains('13:00', $times);
        $this->assertNotContains('15:00', $times);
        $this->assertContains('16:00', $times);
        $this->assertContains('12:00', $times);
    }

    // =====================================================================
    // Staff selection on vs off (spec §9)
    // =====================================================================

    public function test_with_staff_selection_off_each_time_appears_once(): void
    {
        $date = $this->date('2026-09-22');

        // A second stylist with an identical schedule.
        $reem = Staff::factory()->forStore($this->store)->create([
            'name' => 'Reem',
            'branch_id' => $this->branch->id,
        ]);
        foreach (range(0, 6) as $day) {
            $reem->schedules()->create([
                'day_of_week' => $day, 'starts_at' => '10:00', 'ends_at' => '22:00',
            ]);
        }

        $this->store->bookingSettings->update(['staff_selection' => false]);

        $slots = $this->engine->slotsFor(
            $this->store(),
            $this->hairColor,
            $date,
            $this->branch(),
            null,
            $this->date('2026-09-01'),
        );

        $times = $slots->map(fn (Slot $s) => $s->startsAt->setTimezone(self::TZ)->format('H:i'))->all();

        $this->assertSame(array_values(array_unique($times)), $times, 'Times were duplicated per staff');
        $this->assertNull($slots->first()->staffId, 'Staff identity leaked while selection is disabled');
    }

    public function test_with_staff_selection_on_each_staff_member_is_offered(): void
    {
        $date = $this->date('2026-09-23');

        $reem = Staff::factory()->forStore($this->store)->create([
            'name' => 'Reem', 'branch_id' => $this->branch->id,
        ]);
        foreach (range(0, 6) as $day) {
            $reem->schedules()->create([
                'day_of_week' => $day, 'starts_at' => '10:00', 'ends_at' => '22:00',
            ]);
        }

        $this->store->bookingSettings->update(['staff_selection' => true]);

        $slots = $this->engine->slotsFor(
            $this->store(),
            $this->hairColor,
            $date,
            $this->branch(),
            null,
            $this->date('2026-09-01'),
        );

        $tenAm = $slots->filter(
            fn (Slot $s) => $s->startsAt->setTimezone(self::TZ)->format('H:i') === '10:00'
        );

        $this->assertCount(2, $tenAm, 'Both stylists should be offered at 10:00');
        $this->assertEqualsCanonicalizing(
            [$this->sara->id, $reem->id],
            $tenAm->pluck('staffId')->all(),
        );
    }

    /**
     * Spec §15: a staff member with NO service assignments can perform
     * everything. Getting this backwards makes every zero-setup merchant
     * unbookable.
     */
    public function test_staff_with_no_assignments_can_perform_any_service(): void
    {
        $this->assertTrue($this->sara->canPerform($this->hairColor));

        $times = $this->times($this->date('2026-09-24'), $this->sara());
        $this->assertNotEmpty($times);
    }

    public function test_staff_restricted_to_another_service_is_not_offered(): void
    {
        $facial = Service::factory()->forStore($this->store)->create([
            'name_en' => 'Facial', 'duration_minutes' => 60, 'price' => 180,
        ]);

        // Once Sara has ANY assignment, the list becomes restrictive.
        $this->sara->services()->attach($facial->id);

        $this->assertFalse($this->sara()->canPerform($this->hairColor));
        $this->assertTrue($this->sara()->canPerform($facial));

        $this->assertSame([], $this->times($this->date('2026-09-25'), $this->sara()));
    }

    // =====================================================================
    // The write-path guard (§6.3)
    // =====================================================================

    public function test_is_still_free_detects_a_conflict(): void
    {
        $date = $this->date('2026-09-26');

        Booking::create([
            'store_id' => $this->store->id,
            'branch_id' => $this->branch->id,
            'service_id' => $this->hairColor->id,
            'staff_id' => $this->sara->id,
            'starts_at' => $date->setTime(14, 0)->utc(),
            'ends_at' => $date->setTime(16, 0)->utc(),
            'duration_minutes' => 120,
            'price' => 250,
        ])->transitionTo(BookingStatus::Confirmed);

        // Overlapping — must be refused.
        $this->assertFalse($this->engine->isStillFree(
            $this->sara, $this->branch,
            $date->setTime(15, 0)->utc(), $date->setTime(17, 0)->utc(),
        ));

        // Exactly abutting — allowed, because intervals are half-open.
        $this->assertTrue($this->engine->isStillFree(
            $this->sara, $this->branch,
            $date->setTime(16, 0)->utc(), $date->setTime(18, 0)->utc(),
        ));
    }
}
