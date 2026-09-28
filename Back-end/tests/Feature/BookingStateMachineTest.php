<?php

namespace Tests\Feature;

use App\Domain\Booking\BookingService;
use App\Domain\Booking\BookingStatus;
use App\Domain\Booking\Exceptions\InvalidStatusTransition;
use App\Domain\Booking\Exceptions\SlotNoLongerAvailable;
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
 * The booking state machine (spec §19) and the double-booking guard (§6.3).
 */
class BookingStateMachineTest extends TestCase
{
    use RefreshDatabase;

    private const TZ = 'Asia/Riyadh';

    private Store $store;

    private Branch $branch;

    private Staff $sara;

    private Service $haircut;

    private BookingService $bookings;

    protected function setUp(): void
    {
        parent::setUp();

        $merchant = Merchant::factory()->create();
        app(TenantContext::class)->setTenant($merchant);

        $this->store = Store::factory()->create(['merchant_id' => $merchant->id]);

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $this->store->id,
            'min_lead_time_minutes' => 0,
            'max_advance_days' => 365,
        ]));

        $this->branch = Branch::factory()->forStore($this->store)->create([
            'slot_interval_minutes' => 15,
        ]);

        foreach (range(0, 6) as $day) {
            $this->branch->schedules()->create([
                'day_of_week' => $day, 'opens_at' => '10:00', 'closes_at' => '22:00',
            ]);
        }

        $this->sara = Staff::factory()->forStore($this->store)->create([
            'name' => 'Sara', 'branch_id' => $this->branch->id,
        ]);

        foreach (range(0, 6) as $day) {
            $this->sara->schedules()->create([
                'day_of_week' => $day, 'starts_at' => '10:00', 'ends_at' => '22:00',
            ]);
        }

        $this->haircut = Service::factory()->forStore($this->store)->create([
            'name_en' => 'Hair Cut', 'duration_minutes' => 30, 'price' => 100,
            'buffer_after_minutes' => 0,
        ]);

        $this->bookings = app(BookingService::class);
    }

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
        return Staff::with(['schedules', 'services'])->findOrFail($this->sara->id);
    }

    private function at(string $ymd, int $hour): CarbonImmutable
    {
        return CarbonImmutable::parse($ymd, self::TZ)->setTime($hour, 0);
    }

    // =====================================================================
    // Valid and invalid transitions (spec §19)
    // =====================================================================

    public function test_the_happy_path_walks_the_whole_machine(): void
    {
        $booking = $this->makeBooking('2026-10-01', 12);

        // auto_confirm is on, so creation already moved it to confirmed.
        $this->assertSame(BookingStatus::Confirmed, $booking->booking_status);

        $booking->transitionTo(BookingStatus::CheckedIn, 'merchant');
        $this->assertSame(BookingStatus::CheckedIn, $booking->booking_status);
        $this->assertNotNull($booking->checked_in_at);

        $booking->transitionTo(BookingStatus::Completed, 'merchant');
        $this->assertSame(BookingStatus::Completed, $booking->booking_status);
        $this->assertNotNull($booking->completed_at);
    }

    public function test_a_completed_booking_is_terminal(): void
    {
        $booking = $this->makeBooking('2026-10-02', 12);
        $booking->transitionTo(BookingStatus::CheckedIn, 'merchant');
        $booking->transitionTo(BookingStatus::Completed, 'merchant');

        $this->assertTrue($booking->booking_status->isTerminal());

        $this->expectException(InvalidStatusTransition::class);
        $booking->transitionTo(BookingStatus::Cancelled, 'merchant');
    }

    public function test_a_cancelled_booking_cannot_be_revived(): void
    {
        $booking = $this->makeBooking('2026-10-03', 12);
        $booking->transitionTo(BookingStatus::Cancelled, 'customer');

        $this->expectException(InvalidStatusTransition::class);
        $booking->transitionTo(BookingStatus::Confirmed, 'merchant');
    }

    public function test_you_cannot_skip_from_pending_to_completed(): void
    {
        $this->store->bookingSettings->update(['auto_confirm' => false]);
        $booking = $this->makeBooking('2026-10-04', 12);

        $this->assertSame(BookingStatus::Pending, $booking->booking_status);

        $this->expectException(InvalidStatusTransition::class);
        $booking->transitionTo(BookingStatus::Completed, 'merchant');
    }

    public function test_a_no_show_can_be_recorded_from_confirmed_or_checked_in(): void
    {
        $a = $this->makeBooking('2026-10-05', 12);
        $a->transitionTo(BookingStatus::NoShow, 'merchant');
        $this->assertSame(BookingStatus::NoShow, $a->booking_status);

        $b = $this->makeBooking('2026-10-05', 14);
        $b->transitionTo(BookingStatus::CheckedIn, 'merchant');
        $b->transitionTo(BookingStatus::NoShow, 'merchant');
        $this->assertSame(BookingStatus::NoShow, $b->booking_status);
    }

    public function test_every_transition_is_recorded_in_history(): void
    {
        $booking = $this->makeBooking('2026-10-06', 12);
        $booking->transitionTo(BookingStatus::CheckedIn, 'merchant', null, 'Walked in');
        $booking->transitionTo(BookingStatus::Completed, 'merchant');

        $history = $booking->statusHistory()->orderBy('id')->get();

        // pending->confirmed (auto), confirmed->checked_in, checked_in->completed
        $this->assertCount(3, $history);
        $this->assertSame('pending', $history[0]->from_status);
        $this->assertSame('confirmed', $history[0]->to_status);
        $this->assertSame('Walked in', $history[1]->reason);
        $this->assertSame('completed', $history[2]->to_status);
    }

    public function test_cancelling_records_who_did_it(): void
    {
        $booking = $this->makeBooking('2026-10-07', 12);
        $booking->transitionTo(BookingStatus::Cancelled, 'merchant', null, 'Stylist ill');

        $this->assertSame('merchant', $booking->cancelled_by);
        $this->assertSame('Stylist ill', $booking->cancellation_reason);
        $this->assertNotNull($booking->cancelled_at);
    }

    // =====================================================================
    // The double-booking guard (§6.3)
    // =====================================================================

    /**
     * The core guarantee: the second attempt at an occupied slot is refused by
     * the re-check inside the transaction, even though availability may have
     * shown it as free a moment earlier.
     */
    public function test_booking_the_same_slot_twice_is_refused(): void
    {
        $when = $this->at('2026-10-10', 15);

        $first = $this->bookings->create(
            $this->store(), $this->haircut, $when, $this->branch(), $this->sara(),
        );

        $this->assertNotNull($first->id);

        $this->expectException(SlotNoLongerAvailable::class);

        $this->bookings->create(
            $this->store(), $this->haircut, $when, $this->branch(), $this->sara(),
        );
    }

    public function test_an_overlapping_but_not_identical_slot_is_also_refused(): void
    {
        // 15:00-15:30 exists; 15:15 would start inside it.
        $this->bookings->create(
            $this->store(), $this->haircut, $this->at('2026-10-11', 15),
            $this->branch(), $this->sara(),
        );

        $this->expectException(SlotNoLongerAvailable::class);

        $this->bookings->create(
            $this->store(), $this->haircut,
            $this->at('2026-10-11', 15)->addMinutes(15),
            $this->branch(), $this->sara(),
        );
    }

    public function test_an_abutting_slot_is_allowed(): void
    {
        // Half-open intervals: 15:00-15:30 must not block 15:30-16:00.
        $this->bookings->create(
            $this->store(), $this->haircut, $this->at('2026-10-12', 15),
            $this->branch(), $this->sara(),
        );

        $second = $this->bookings->create(
            $this->store(), $this->haircut,
            $this->at('2026-10-12', 15)->addMinutes(30),
            $this->branch(), $this->sara(),
        );

        $this->assertNotNull($second->id);
        $this->assertSame(2, Booking::count());
    }

    public function test_a_cancelled_booking_frees_the_slot_for_a_new_one(): void
    {
        $when = $this->at('2026-10-13', 16);

        $first = $this->bookings->create(
            $this->store(), $this->haircut, $when, $this->branch(), $this->sara(),
        );
        $first->transitionTo(BookingStatus::Cancelled, 'customer');

        $second = $this->bookings->create(
            $this->store(), $this->haircut, $when, $this->branch(), $this->sara(),
        );

        $this->assertNotNull($second->id);
    }

    // =====================================================================
    // Auto-assignment when staff selection is off (spec §9, §15)
    // =====================================================================

    public function test_staff_is_assigned_automatically_when_not_requested(): void
    {
        $booking = $this->bookings->create(
            $this->store(), $this->haircut, $this->at('2026-10-14', 11), $this->branch(),
        );

        $this->assertSame(
            $this->sara->id,
            $booking->staff_id,
            'The backend should have assigned the only available stylist.'
        );
    }

    public function test_auto_assignment_spreads_load_across_staff(): void
    {
        $reem = Staff::factory()->forStore($this->store)->create([
            'name' => 'Reem', 'branch_id' => $this->branch->id,
        ]);
        foreach (range(0, 6) as $day) {
            $reem->schedules()->create([
                'day_of_week' => $day, 'starts_at' => '10:00', 'ends_at' => '22:00',
            ]);
        }

        // Three bookings at different times, none requesting a stylist.
        $assigned = [];
        foreach ([11, 13, 15] as $hour) {
            $assigned[] = $this->bookings->create(
                $this->store(), $this->haircut, $this->at('2026-10-15', $hour), $this->branch(),
            )->staff_id;
        }

        // Load balancing should not pile all three onto one person.
        $this->assertGreaterThan(
            1,
            count(array_unique($assigned)),
            'Auto-assignment gave every booking to the same stylist.'
        );
    }

    public function test_auto_assignment_fails_when_everyone_is_busy(): void
    {
        $when = $this->at('2026-10-16', 17);

        $this->bookings->create($this->store(), $this->haircut, $when, $this->branch());

        // Sara is the only stylist and is now taken.
        $this->expectException(SlotNoLongerAvailable::class);
        $this->bookings->create($this->store(), $this->haircut, $when, $this->branch());
    }

    // =====================================================================
    // Rescheduling (spec §22)
    // =====================================================================

    public function test_rescheduling_re_checks_availability(): void
    {
        $booking = $this->bookings->create(
            $this->store(), $this->haircut, $this->at('2026-10-20', 12),
            $this->branch(), $this->sara(),
        );

        // Occupy the target slot with someone else's booking.
        $this->bookings->create(
            $this->store(), $this->haircut, $this->at('2026-10-20', 14),
            $this->branch(), $this->sara(),
        );

        $this->expectException(SlotNoLongerAvailable::class);

        $this->bookings->reschedule($booking, $this->at('2026-10-20', 14), $this->sara());
    }

    public function test_rescheduling_into_a_free_slot_succeeds(): void
    {
        $booking = $this->bookings->create(
            $this->store(), $this->haircut, $this->at('2026-10-21', 12),
            $this->branch(), $this->sara(),
        );

        $moved = $this->bookings->reschedule($booking, $this->at('2026-10-21', 18), $this->sara());

        $this->assertSame(
            '18:00',
            $moved->starts_at->setTimezone(self::TZ)->format('H:i'),
        );
    }

    /**
     * A booking must not conflict with itself when moved a short distance.
     */
    public function test_rescheduling_ignores_the_booking_being_moved(): void
    {
        $booking = $this->bookings->create(
            $this->store(), $this->haircut, $this->at('2026-10-22', 12),
            $this->branch(), $this->sara(),
        );

        // 12:00-12:30 shifting to 12:15 overlaps its own old window.
        $moved = $this->bookings->reschedule(
            $booking, $this->at('2026-10-22', 12)->addMinutes(15), $this->sara(),
        );

        $this->assertSame('12:15', $moved->starts_at->setTimezone(self::TZ)->format('H:i'));
    }

    private function makeBooking(string $ymd, int $hour): Booking
    {
        return $this->bookings->create(
            $this->store(), $this->haircut, $this->at($ymd, $hour),
            $this->branch(), $this->sara(),
        );
    }
}
