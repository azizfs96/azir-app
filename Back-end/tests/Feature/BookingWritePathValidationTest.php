<?php

namespace Tests\Feature;

use App\Domain\Booking\BookingService;
use App\Domain\Booking\Exceptions\SlotNoLongerAvailable;
use App\Domain\Scheduling\AvailabilityEngine;
use App\Models\BookingSettings;
use App\Models\Branch;
use App\Models\Merchant;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use App\Models\TimeOff;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * THE WRITE PATH MUST ENFORCE WHAT AVAILABILITY PROMISES (audit BL-1..4, BL-8)
 *
 * slotsFor() honoured working hours, rosters, time-off, capability, branch
 * membership and the booking window; create()/reschedule() honoured NONE of
 * them — the only write-time check was "no colliding booking". Probes proved
 * the API happily created confirmed bookings at 03:00, during a stylist's
 * recorded vacation, two days in the past, 90 days beyond the window, with a
 * manicure-only stylist for a haircut, and with a branch-A stylist at branch B.
 *
 * Every test here books through BookingService — the layer every current and
 * future API path funnels through — so the rule cannot be bypassed by a new
 * controller the way it was bypassed by a crafted request.
 * ============================================================================
 */
class BookingWritePathValidationTest extends TestCase
{
    use RefreshDatabase;

    private const TZ = 'Asia/Riyadh';

    private Store $store;

    private Branch $branch;

    /** Rostered daily 09:00-21:00. */
    private Staff $reem;

    /** Employed and bookable but has NO schedule rows at all. */
    private Staff $sara;

    private Service $haircut;

    protected function setUp(): void
    {
        parent::setUp();

        $merchant = Merchant::factory()->create();
        app(TenantContext::class)->setTenant($merchant);

        $this->store = Store::factory()->create(['merchant_id' => $merchant->id]);

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $this->store->id,
            'min_lead_time_minutes' => 0,
            'max_advance_days' => 30,
            'staff_selection' => true,
        ]));

        $this->branch = Branch::factory()->forStore($this->store)->create([
            'slot_interval_minutes' => 30,
            'buffer_before_minutes' => 0,
            'buffer_after_minutes' => 0,
        ]);

        foreach (range(0, 6) as $day) {
            $this->branch->schedules()->create([
                'day_of_week' => $day, 'opens_at' => '09:00', 'closes_at' => '21:00',
            ]);
        }

        $this->sara = Staff::factory()->forStore($this->store)->create([
            'name' => 'Sara', 'branch_id' => $this->branch->id,
        ]);

        $this->reem = Staff::factory()->forStore($this->store)->create([
            'name' => 'Reem', 'branch_id' => $this->branch->id,
        ]);

        foreach (range(0, 6) as $day) {
            $this->reem->schedules()->create([
                'day_of_week' => $day, 'starts_at' => '09:00', 'ends_at' => '21:00',
            ]);
        }

        $this->haircut = Service::factory()->forStore($this->store)->create([
            'duration_minutes' => 60, 'buffer_after_minutes' => 0, 'price' => 100,
        ]);

        app(TenantContext::class)->setTenant(null);
    }

    // ---- helpers ---------------------------------------------------------

    private function at(string $dayTime): CarbonImmutable
    {
        return CarbonImmutable::parse($dayTime, self::TZ);
    }

    private function svc(): BookingService
    {
        return app(BookingService::class);
    }

    private function freshStore(): Store
    {
        return Store::query()->withoutGlobalScopes()
            ->with('bookingSettings')->find($this->store->id);
    }

    private function loaded(Staff $staff): Staff
    {
        return Staff::query()->withoutGlobalScopes()
            ->with(['schedules', 'services'])->find($staff->id);
    }

    private function asTenant(callable $fn): void
    {
        app(TenantContext::class)->setTenant(Merchant::find($this->store->merchant_id));
        $fn();
        app(TenantContext::class)->setTenant(null);
    }

    private function tryCreate(CarbonImmutable $when, ?Staff $staff, ?Branch $branch = null): \App\Models\Booking
    {
        return $this->svc()->create(
            store: $this->freshStore(),
            service: $this->haircut,
            startsAt: $when,
            branch: $branch ?? $this->branch,
            requestedStaff: $staff === null ? null : $this->loaded($staff),
        );
    }

    private function assertRefused(callable $attempt, string $why): void
    {
        try {
            $booking = $attempt();
            $this->fail("{$why} — but the booking was ACCEPTED (id {$booking->id}).");
        } catch (SlotNoLongerAvailable) {
            $this->assertTrue(true);
        }
    }

    // ---- BL-1: hours, time-off, past -------------------------------------

    public function test_refuses_a_booking_outside_working_hours(): void
    {
        $this->assertRefused(
            fn () => $this->tryCreate($this->at('+3 days 03:00'), $this->reem),
            'The branch is closed and nobody is rostered at 03:00',
        );
    }

    public function test_refuses_a_booking_that_runs_past_closing(): void
    {
        // 20:30 + 60min ends 21:30, past the 21:00 close — availability
        // correctly never offers this start; the write path must agree.
        $this->assertRefused(
            fn () => $this->tryCreate($this->at('+3 days 20:30'), $this->reem),
            'The service cannot finish before closing',
        );
    }

    public function test_refuses_a_booking_during_staff_time_off(): void
    {
        $this->asTenant(fn () => TimeOff::create([
            'staff_id' => $this->reem->id,
            'starts_at' => $this->at('+2 days 00:00')->utc(),
            'ends_at' => $this->at('+5 days 00:00')->utc(),
            'reason' => 'Vacation',
        ]));

        $this->assertRefused(
            fn () => $this->tryCreate($this->at('+3 days 12:00'), $this->reem),
            'The stylist is on recorded vacation',
        );
    }

    public function test_refuses_a_booking_during_branch_time_off(): void
    {
        $this->asTenant(fn () => TimeOff::create([
            'branch_id' => $this->branch->id,
            'starts_at' => $this->at('+3 days 00:00')->utc(),
            'ends_at' => $this->at('+4 days 00:00')->utc(),
            'reason' => 'Eid',
        ]));

        $this->assertRefused(
            fn () => $this->tryCreate($this->at('+3 days 12:00'), $this->reem),
            'The whole branch is closed for the holiday',
        );
    }

    public function test_refuses_a_booking_in_the_past(): void
    {
        $this->assertRefused(
            fn () => $this->tryCreate($this->at('-2 days 12:00'), $this->reem),
            'The requested time is in the past',
        );
    }

    // ---- BL-8: the booking window ----------------------------------------

    public function test_refuses_a_booking_beyond_the_advance_window(): void
    {
        $this->assertRefused(
            fn () => $this->tryCreate($this->at('+90 days 12:00'), $this->reem),
            'The merchant only takes bookings 30 days ahead',
        );
    }

    public function test_the_last_day_of_the_window_is_bookable(): void
    {
        // slotsFor() treats day N as inclusive; the write path must use the
        // SAME boundary or the two will disagree at the edge.
        $booking = $this->tryCreate($this->at('+30 days 12:00'), $this->reem);

        $this->assertNotNull($booking->id);
    }

    public function test_refuses_a_booking_inside_the_lead_time(): void
    {
        BookingSettings::withoutGlobalScopes()
            ->where('store_id', $this->store->id)
            ->update(['min_lead_time_minutes' => 3 * 24 * 60]);

        $this->assertRefused(
            fn () => $this->tryCreate($this->at('+1 day 12:00'), $this->reem),
            'The merchant requires 3 days notice',
        );
    }

    // ---- BL-4: capability -------------------------------------------------

    public function test_refuses_a_stylist_who_cannot_perform_the_service(): void
    {
        $this->asTenant(function (): void {
            $manicure = Service::factory()->forStore($this->store)->create([
                'duration_minutes' => 30, 'buffer_after_minutes' => 0, 'price' => 50,
            ]);
            // Assigning ANY service restricts Reem to exactly that set (§15).
            $this->reem->services()->attach($manicure->id);
        });

        $this->assertRefused(
            fn () => $this->tryCreate($this->at('+3 days 12:00'), $this->reem),
            'Reem is manicure-only and cannot perform a haircut',
        );
    }

    public function test_refuses_a_stylist_with_no_roster_at_all(): void
    {
        $this->assertRefused(
            fn () => $this->tryCreate($this->at('+3 days 12:00'), $this->sara),
            'Sara has no schedule rows and therefore no working hours',
        );
    }

    // ---- BL-3: branch membership ------------------------------------------

    public function test_refuses_a_stylist_from_another_branch(): void
    {
        $branchB = null;

        $this->asTenant(function () use (&$branchB): void {
            $branchB = Branch::factory()->forStore($this->store)->create([
                'slot_interval_minutes' => 30,
                'buffer_before_minutes' => 0,
                'buffer_after_minutes' => 0,
            ]);

            foreach (range(0, 6) as $day) {
                $branchB->schedules()->create([
                    'day_of_week' => $day, 'opens_at' => '09:00', 'closes_at' => '21:00',
                ]);
            }
        });

        // Reem belongs to branch A; the customer asks for her AT BRANCH B.
        $this->assertRefused(
            fn () => $this->tryCreate($this->at('+3 days 12:00'), $this->reem, $branchB),
            'Reem works at branch A, not branch B',
        );

        // And the READ path must stop advertising her there too.
        $slots = app(AvailabilityEngine::class)->slotsFor(
            $this->freshStore(), $this->haircut, $this->at('+3 days 00:00'),
            $branchB, $this->loaded($this->reem),
        );

        $this->assertCount(
            0,
            $slots,
            'Availability still offers a branch-A stylist under branch B.',
        );
    }

    public function test_a_shared_stylist_books_at_any_branch(): void
    {
        $branchB = null;

        $this->asTenant(function () use (&$branchB): void {
            $branchB = Branch::factory()->forStore($this->store)->create([
                'slot_interval_minutes' => 30,
                'buffer_before_minutes' => 0,
                'buffer_after_minutes' => 0,
            ]);

            foreach (range(0, 6) as $day) {
                $branchB->schedules()->create([
                    'day_of_week' => $day, 'opens_at' => '09:00', 'closes_at' => '21:00',
                ]);
            }

            // branch_id NULL = works everywhere (spec §15).
            Staff::withoutGlobalScopes()->find($this->reem->id)->update(['branch_id' => null]);
        });

        $booking = $this->tryCreate($this->at('+3 days 12:00'), $this->reem, $branchB);

        $this->assertSame($branchB->id, $booking->branch_id);
    }

    // ---- BL-2: auto-assignment respects rosters ---------------------------

    public function test_auto_assignment_never_picks_an_unrostered_stylist(): void
    {
        // Sara has zero bookings (because she never works!) so load-ranking
        // used to hand her every "any available" booking.
        $booking = $this->tryCreate($this->at('+3 days 12:00'), null);

        $this->assertSame(
            $this->reem->id,
            $booking->staff_id,
            'Auto-assignment chose a stylist who is not rostered at that time.',
        );
    }

    public function test_auto_assignment_refuses_when_no_roster_covers_the_time(): void
    {
        $this->asTenant(function (): void {
            // Shrink Reem to mornings only; Sara still has no roster.
            $this->reem->schedules()->delete();

            foreach (range(0, 6) as $day) {
                $this->reem->schedules()->create([
                    'day_of_week' => $day, 'starts_at' => '09:00', 'ends_at' => '13:00',
                ]);
            }
        });

        $this->assertRefused(
            fn () => $this->tryCreate($this->at('+3 days 15:00'), null),
            'Nobody is rostered at 15:00',
        );
    }

    // ---- reschedule must revalidate like a fresh booking -------------------

    public function test_reschedule_is_validated_like_a_fresh_booking(): void
    {
        $booking = $this->tryCreate($this->at('+3 days 12:00'), $this->reem);

        $this->assertRefused(
            fn () => $this->svc()->reschedule($booking, $this->at('+3 days 03:00')),
            'Rescheduling to 03:00 must fail exactly as creating at 03:00 would',
        );

        $this->assertRefused(
            fn () => $this->svc()->reschedule($booking, $this->at('-1 day 12:00')),
            'Rescheduling into the past must be refused',
        );

        $this->assertRefused(
            fn () => $this->svc()->reschedule($booking, $this->at('+90 days 12:00')),
            'Rescheduling beyond the advance window must be refused',
        );

        // The booking must be UNTOUCHED after every refused attempt.
        $fresh = $booking->fresh();
        $this->assertSame(
            $this->at('+3 days 12:00')->utc()->toIso8601String(),
            $fresh->starts_at->utc()->toIso8601String(),
            'A refused reschedule corrupted the original booking.',
        );
    }

    // ---- controls: everything legitimate keeps working ---------------------

    public function test_a_valid_booking_still_books(): void
    {
        $booking = $this->tryCreate($this->at('+3 days 12:00'), $this->reem);

        $this->assertSame('confirmed', $booking->booking_status->value);
    }

    public function test_a_valid_reschedule_still_works(): void
    {
        $booking = $this->tryCreate($this->at('+3 days 12:00'), $this->reem);

        $moved = $this->svc()->reschedule($booking, $this->at('+4 days 15:00'));

        $this->assertSame(
            '15:00',
            $moved->starts_at->setTimezone(self::TZ)->format('H:i'),
        );
    }

    public function test_a_cross_midnight_shift_booking_remains_valid(): void
    {
        // Friday night shift 20:00-02:00: a booking at Saturday 01:00 belongs
        // to FRIDAY's shift. Naive "check Saturday's windows" validation would
        // wrongly refuse it — this is the control that keeps the fix honest.
        $friday = CarbonImmutable::now(self::TZ)->next('Friday');

        if ($friday->diffInDays(CarbonImmutable::now(self::TZ)->startOfDay()) > 28) {
            $this->markTestSkipped('Friday falls outside the 30-day fixture window.');
        }

        $this->asTenant(function (): void {
            $this->branch->schedules()->where('day_of_week', 5)->delete();
            $this->branch->schedules()->create([
                'day_of_week' => 5, 'opens_at' => '20:00', 'closes_at' => '02:00',
            ]);

            $this->reem->schedules()->where('day_of_week', 5)->delete();
            $this->reem->schedules()->create([
                'day_of_week' => 5, 'starts_at' => '20:00', 'ends_at' => '02:00',
            ]);
        });

        $booking = $this->tryCreate($friday->setTime(1, 0)->addDay(), $this->reem);

        $this->assertNotNull($booking->id);
    }

    public function test_a_staffless_store_validates_branch_hours(): void
    {
        $this->asTenant(function (): void {
            // The store genuinely employs nobody: the branch is the resource.
            Staff::withoutGlobalScopes()
                ->where('store_id', $this->store->id)
                ->update(['is_bookable' => false]);
        });

        $inside = $this->svc()->create(
            store: $this->freshStore(),
            service: $this->haircut,
            startsAt: $this->at('+3 days 12:00'),
            branch: $this->branch,
        );
        $this->assertNull($inside->staff_id);

        $this->assertRefused(
            fn () => $this->svc()->create(
                store: $this->freshStore(),
                service: $this->haircut,
                startsAt: $this->at('+3 days 03:00'),
                branch: $this->branch,
            ),
            'The branch itself is closed at 03:00',
        );
    }
}
