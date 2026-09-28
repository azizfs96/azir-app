<?php

namespace App\Domain\Scheduling;

use App\Domain\Booking\BookingStatus;
use App\Models\Booking;
use App\Models\Branch;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use App\Models\TimeOff;
use App\Support\TimeRange;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;

/**
 * ============================================================================
 * THE AVAILABILITY ENGINE (spec §17 — "This is critical")
 *
 * Given (store, service, date, [branch], [staff]) it returns bookable start
 * times, accounting for:
 *
 *   · branch working hours          · existing bookings
 *   · staff working hours           · service duration
 *   · staff breaks                  · buffer time
 *   · days off / time off           · staff-service compatibility
 *
 * The algorithm is documented step by step in ARCHITECTURE.md §6.1 and the
 * steps below are numbered to match it.
 *
 * IMPORTANT: what this returns is ADVISORY. Two customers can both be shown the
 * same slot at the same moment. The authoritative check happens under a row
 * lock at write time — see BookingService and §6.3. Never treat a slot returned
 * here as reserved.
 *
 * TIMEZONES: all reasoning happens in the STORE's local timezone, because
 * "Sunday 10:00" is a local-clock concept. Bookings are stored UTC, so
 * conversion happens at the boundaries only (§5.4).
 * ============================================================================
 */
class AvailabilityEngine
{
    public function __construct(
        private readonly StaffAssigner $staffAssigner,
    ) {}

    /**
     * Bookable slots for one day.
     *
     * @param  Staff|null  $requestedStaff  Set only when the customer picked someone
     * @return Collection<int, Slot>
     */
    public function slotsFor(
        Store $store,
        Service $service,
        CarbonImmutable $date,
        ?Branch $branch = null,
        ?Staff $requestedStaff = null,
        ?CarbonImmutable $now = null,
    ): Collection {
        $timezone = $store->timezone ?: config('wasla.default_timezone');
        $now ??= CarbonImmutable::now();

        // ---- Step 1: resolve the branch ---------------------------------
        // If the merchant has one branch we never asked the customer (spec §16),
        // so resolve it here rather than expecting it to be supplied.
        $branch ??= $store->defaultBranch();

        if ($branch === null) {
            return collect();
        }

        $settings = $store->bookingSettings;

        // ---- Step 5 (early): is this date inside the bookable window? ----
        // Done before any query — a date outside the window has no slots at all,
        // so there is no point loading schedules for it.
        $localDate = $date->setTimezone($timezone)->startOfDay();

        if ($settings !== null) {
            $lastBookableDay = $now->setTimezone($timezone)
                ->startOfDay()
                ->addDays($settings->max_advance_days);

            if ($localDate->greaterThan($lastBookableDay)) {
                return collect();
            }
        }

        // ---- Step 2: candidate staff ------------------------------------
        $candidates = $this->candidateStaff($store, $service, $branch, $requestedStaff);

        /*
         * A merchant with NO staff at all is valid (spec §15): the branch itself
         * becomes the bookable resource.
         *
         * But "no candidates" and "no staff" are different things, and conflating
         * them is a security-adjacent bug: if the customer asked for a stylist who
         * cannot perform this service — or every stylist was filtered out — falling
         * back to branch-level slots would happily offer appointments that nobody
         * is qualified or rostered to serve.
         *
         * So the fallback is allowed only when the store genuinely employs nobody.
         */
        $branchIsTheResource = false;

        if ($candidates->isEmpty()) {
            $storeEmploysStaff = Staff::query()
                ->where('store_id', $store->id)
                ->bookable()
                ->exists();

            if ($storeEmploysStaff) {
                return collect();
            }

            $branchIsTheResource = true;
        }

        // ---- Step 3: free windows ---------------------------------------
        $branchWindows = $this->branchWindows($branch, $localDate, $timezone);

        if ($branchWindows === []) {
            return collect();
        }

        // Duration this booking will occupy, including the service's own buffer
        // and the branch's turnaround padding.
        $slotInterval = max(5, $branch->slot_interval_minutes ?: 15);
        $earliestStart = $settings !== null
            ? $now->addMinutes($settings->min_lead_time_minutes)
            : $now;

        if ($branchIsTheResource) {
            $free = TimeRange::subtractAll(
                $branchWindows,
                array_merge(
                    $this->branchTimeOffBlockers($branch, $localDate, $timezone),
                    $this->bookingBlockers(
                        Booking::query()->where('branch_id', $branch->id)->whereNull('staff_id'),
                        $branch,
                        $localDate,
                        $timezone,
                    ),
                ),
            );

            $required = $this->requiredMinutes($service, null, $branch);

            return $this->generateSlots($free, $required, $slotInterval, $earliestStart, null)
                ->values();
        }

        $branchTimeOff = $this->branchTimeOffBlockers($branch, $localDate, $timezone);

        $slots = collect();

        foreach ($candidates as $staff) {
            $windows = $this->staffWindows($staff, $localDate, $timezone, $branchWindows);

            if ($windows === []) {
                continue;
            }

            $blockers = array_merge(
                $branchTimeOff,
                $this->staffTimeOffBlockers($staff, $localDate, $timezone),
                $this->bookingBlockers(
                    Booking::query()->where('staff_id', $staff->id),
                    $branch,
                    $localDate,
                    $timezone,
                ),
            );

            $free = TimeRange::subtractAll($windows, $blockers);
            $required = $this->requiredMinutes($service, $staff, $branch);

            $slots = $slots->concat(
                $this->generateSlots($free, $required, $slotInterval, $earliestStart, $staff)
            );
        }

        // ---- Step 6: union across staff ---------------------------------
        return $this->union($slots, $requestedStaff !== null || (bool) $settings?->staff_selection);
    }

    /**
     * Step 2 — who could perform this service at this branch?
     *
     * @return Collection<int, Staff>
     */
    private function candidateStaff(
        Store $store,
        Service $service,
        Branch $branch,
        ?Staff $requestedStaff,
    ): Collection {
        if ($requestedStaff !== null) {
            // The caller may hand us a bare model; staffWindows() needs schedules
            // and canPerform() needs services. Load explicitly rather than
            // relying on lazy loading, which is disabled outside production
            // precisely to keep this engine free of N+1s.
            $requestedStaff->loadMissing(['services', 'schedules']);

            // Trust nothing: a client-supplied staff id must still be bookable,
            // still able to perform this service, and actually work at THIS
            // branch — a branch-A stylist's roster happily intersects branch
            // B's opening hours, which is how cross-branch slots leaked.
            $eligible = $requestedStaff->is_active
                && $requestedStaff->is_bookable
                && $requestedStaff->canPerform($service)
                && ($requestedStaff->branch_id === null
                    || (int) $requestedStaff->branch_id === (int) $branch->id);

            return $eligible ? collect([$requestedStaff]) : collect();
        }

        return Staff::query()
            ->where('store_id', $store->id)
            // Staff with no branch are shared across branches.
            ->where(fn ($q) => $q->where('branch_id', $branch->id)->orWhereNull('branch_id'))
            ->bookable()
            ->capableOf($service)
            // schedules is required by staffWindows(); loading it here keeps the
            // whole day's availability to a fixed number of queries.
            ->with(['services', 'schedules'])
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get();
    }

    /**
     * Step 3a — the branch's opening windows for this local date.
     *
     * Multiple rows per weekday are normal: split shifts around prayer times
     * (§12 risk 9). Each becomes its own window.
     *
     * @return array<int, TimeRange>
     */
    private function branchWindows(Branch $branch, CarbonImmutable $localDate, string $timezone): array
    {
        $rows = $branch->schedules
            ->where('day_of_week', $localDate->dayOfWeek)
            ->where('is_closed', false);

        $windows = [];

        foreach ($rows as $row) {
            $window = $this->toRange($localDate, $row->opens_at, $row->closes_at, $timezone);

            if ($window !== null) {
                $windows[] = $window;
            }
        }

        return TimeRange::merge($windows);
    }

    /**
     * Step 3b — a staff member's working windows, intersected with the branch's.
     *
     * The intersection matters: a stylist rostered until midnight cannot be
     * booked past closing time.
     *
     * @param  array<int, TimeRange>  $branchWindows
     * @return array<int, TimeRange>
     */
    private function staffWindows(
        Staff $staff,
        CarbonImmutable $localDate,
        string $timezone,
        array $branchWindows,
    ): array {
        $rows = $staff->schedules
            ->where('day_of_week', $localDate->dayOfWeek)
            ->where('is_off', false);

        $windows = [];

        foreach ($rows as $row) {
            $shift = $this->toRange($localDate, $row->starts_at, $row->ends_at, $timezone);

            if ($shift === null) {
                continue;
            }

            // Intersect with each branch window — a split branch day can cut a
            // continuous staff shift into two bookable pieces.
            foreach ($branchWindows as $branchWindow) {
                $overlap = $shift->intersect($branchWindow);

                if ($overlap !== null) {
                    $windows[] = $overlap;
                }
            }
        }

        $windows = TimeRange::merge($windows);

        // Carve out the break.
        foreach ($rows as $row) {
            if (! $row->hasBreak()) {
                continue;
            }

            $break = $this->toRange($localDate, $row->break_starts_at, $row->break_ends_at, $timezone);

            if ($break !== null) {
                $windows = TimeRange::subtractAll($windows, [$break]);
            }
        }

        return $windows;
    }

    /**
     * Existing bookings, expanded by the branch's turnaround buffers.
     *
     * Only statuses that actually hold the slot block it — a cancelled booking
     * releases its time (BookingStatus::blocksAvailability).
     *
     * @param  \Illuminate\Database\Eloquent\Builder<Booking>  $query
     * @return array<int, TimeRange>
     */
    private function bookingBlockers(
        $query,
        Branch $branch,
        CarbonImmutable $localDate,
        string $timezone,
    ): array {
        // Widen the fetch window by a day either side so a booking that starts
        // late the previous night and runs past midnight is still seen.
        $dayStart = $localDate->setTimezone($timezone)->startOfDay()->utc();
        $dayEnd = $localDate->setTimezone($timezone)->endOfDay()->utc();

        $bookings = $query
            ->whereIn('booking_status', BookingStatus::blockingValues())
            ->where('starts_at', '<', $dayEnd->addDay())
            ->where('ends_at', '>', $dayStart->subDay())
            ->get(['id', 'starts_at', 'ends_at']);

        $blockers = [];

        foreach ($bookings as $booking) {
            $blockers[] = new TimeRange(
                $booking->starts_at->utc()->subMinutes($branch->buffer_before_minutes),
                $booking->ends_at->utc()->addMinutes($branch->buffer_after_minutes),
            );
        }

        return $blockers;
    }

    /** @return array<int, TimeRange> */
    private function staffTimeOffBlockers(Staff $staff, CarbonImmutable $localDate, string $timezone): array
    {
        return $this->timeOffBlockers(
            TimeOff::query()->where('staff_id', $staff->id),
            $localDate,
            $timezone,
        );
    }

    /** @return array<int, TimeRange> */
    private function branchTimeOffBlockers(Branch $branch, CarbonImmutable $localDate, string $timezone): array
    {
        return $this->timeOffBlockers(
            TimeOff::query()->where('branch_id', $branch->id),
            $localDate,
            $timezone,
        );
    }

    /**
     * @param  \Illuminate\Database\Eloquent\Builder<TimeOff>  $query
     * @return array<int, TimeRange>
     */
    private function timeOffBlockers($query, CarbonImmutable $localDate, string $timezone): array
    {
        $dayStart = $localDate->setTimezone($timezone)->startOfDay()->utc();
        $dayEnd = $localDate->setTimezone($timezone)->endOfDay()->utc();

        $rows = $query
            ->where('starts_at', '<', $dayEnd)
            ->where('ends_at', '>', $dayStart)
            ->get(['id', 'starts_at', 'ends_at']);

        return $rows
            ->map(fn (TimeOff $off) => new TimeRange($off->starts_at->utc(), $off->ends_at->utc()))
            ->all();
    }

    /**
     * Step 4 — walk the grid and keep starts whose full duration fits.
     *
     * @param  array<int, TimeRange>  $free
     * @return Collection<int, Slot>
     */
    private function generateSlots(
        array $free,
        int $requiredMinutes,
        int $intervalMinutes,
        CarbonImmutable $earliestStart,
        ?Staff $staff,
    ): Collection {
        $slots = collect();

        foreach ($free as $window) {
            // Skip a window that could never fit the service.
            if ($window->durationMinutes() < $requiredMinutes) {
                continue;
            }

            $cursor = $this->alignToGrid($window->start, $intervalMinutes);

            while (true) {
                $candidate = TimeRange::fromDuration($cursor, $requiredMinutes);

                if (! $window->contains($candidate)) {
                    break;
                }

                // Step 5: honour the minimum lead time — no booking in 10 minutes.
                if ($cursor->greaterThanOrEqualTo($earliestStart)) {
                    $slots->push(new Slot($cursor, $candidate->end, $staff?->id, $staff?->name));
                }

                $cursor = $cursor->addMinutes($intervalMinutes);
            }
        }

        return $slots;
    }

    /**
     * Round a start time up onto the slot grid.
     *
     * Grid is anchored to the hour, so a 15-minute interval yields :00 :15 :30
     * :45 — the times a human expects to see, rather than an arbitrary offset
     * inherited from when the shift happens to begin.
     */
    private function alignToGrid(CarbonImmutable $time, int $intervalMinutes): CarbonImmutable
    {
        $minutesPastHour = (int) $time->format('i');
        $remainder = $minutesPastHour % $intervalMinutes;

        $aligned = $remainder === 0
            ? $time
            : $time->addMinutes($intervalMinutes - $remainder);

        return $aligned->startOfMinute();
    }

    /**
     * Step 6 — collapse per-staff slots into what the customer should see.
     *
     * When staff selection is exposed, every (time, staff) pair is a distinct
     * choice. When it is not, the customer sees each TIME once and the backend
     * decides who serves them (spec §9 Merchant B).
     *
     * @param  Collection<int, Slot>  $slots
     * @return Collection<int, Slot>
     */
    private function union(Collection $slots, bool $exposeStaff): Collection
    {
        if ($exposeStaff) {
            return $slots
                ->sortBy(fn (Slot $slot) => [$slot->startsAt->getTimestamp(), $slot->staffId])
                ->values();
        }

        return $slots
            ->groupBy(fn (Slot $slot) => $slot->startsAt->getTimestamp())
            ->map(fn (Collection $group) => $group->first()->withoutStaff())
            ->sortKeys()
            ->values();
    }

    /**
     * How much wall-clock time this booking consumes: the service duration (or
     * this staff member's override) plus the service's cleanup buffer.
     *
     * The branch's buffer_before/after is applied to EXISTING bookings rather
     * than here, so padding is not double-counted.
     */
    private function requiredMinutes(Service $service, ?Staff $staff, Branch $branch): int
    {
        $duration = $staff !== null
            ? $staff->durationFor($service)
            : $service->duration_minutes;

        return $duration + $service->buffer_after_minutes;
    }

    /**
     * Build a UTC range from a local date + two local clock times.
     *
     * Returns null for a zero-length or inverted row rather than throwing —
     * bad schedule data should make a day unbookable, not 500 the endpoint.
     */
    private function toRange(
        CarbonImmutable $localDate,
        mixed $startTime,
        mixed $endTime,
        string $timezone,
    ): ?TimeRange {
        $start = $this->combine($localDate, (string) $startTime, $timezone);
        $end = $this->combine($localDate, (string) $endTime, $timezone);

        // An end at or before the start means the shift crosses midnight.
        if ($end->lessThanOrEqualTo($start)) {
            $end = $end->addDay();
        }

        if ($end->lessThanOrEqualTo($start)) {
            return null;
        }

        return new TimeRange($start->utc(), $end->utc());
    }

    private function combine(CarbonImmutable $localDate, string $time, string $timezone): CarbonImmutable
    {
        [$hour, $minute] = array_pad(explode(':', $time), 2, '0');

        return $localDate
            ->setTimezone($timezone)
            ->startOfDay()
            ->setTime((int) $hour, (int) $minute);
    }

    /**
     * ========================================================================
     * WHY A REQUESTED SLOT CANNOT BE HONOURED — OR NULL WHEN IT CAN (BL-1..4,8)
     *
     * slotsFor() decides what to DISPLAY; this decides what may be WRITTEN.
     * Until it existed, the write path checked exactly one thing — colliding
     * bookings — and probes proved the API accepted confirmed bookings at
     * 03:00, during a stylist's recorded vacation, in the past, 90 days past
     * the window, with a stylist who cannot perform the service, and with a
     * branch-A stylist at branch B. Availability was law on the read path and
     * folklore on the write path.
     *
     * STATIC validity only. Conflicts with other bookings remain isStillFree()'s
     * job — that one needs the row lock, this one does not (schedules don't
     * change mid-request in any way a lock would fix).
     *
     * Reuses the same private helpers slotsFor() is built from, so the two
     * paths cannot drift: a rule added to one is automatically asked of the
     * other. Returns a short reason for the log; callers translate to their
     * own error contract.
     * ========================================================================
     */
    public function violationFor(
        Store $store,
        Service $service,
        Branch $branch,
        ?Staff $staff,
        CarbonImmutable $startsAt,
        CarbonImmutable $endsAt,
        ?CarbonImmutable $now = null,
    ): ?string {
        $timezone = $store->timezone ?: config('wasla.default_timezone');
        $now ??= CarbonImmutable::now();
        $settings = $store->bookingSettings;

        $startsAt = $startsAt->utc();
        $endsAt = $endsAt->utc();

        // ---- The booking window (identical maths to slotsFor step 5). ----
        // With a zero lead time this is also what refuses the past.
        $earliestStart = $settings !== null
            ? $now->addMinutes($settings->min_lead_time_minutes)
            : $now;

        if ($startsAt->lessThan($earliestStart)) {
            return 'inside the minimum lead time or in the past';
        }

        $localDay = $startsAt->setTimezone($timezone)->startOfDay();

        if ($settings !== null) {
            $lastBookableDay = $now->setTimezone($timezone)
                ->startOfDay()
                ->addDays($settings->max_advance_days);

            // greaterThan, not >=: day N itself is bookable, matching slotsFor.
            if ($localDay->greaterThan($lastBookableDay)) {
                return 'beyond the booking window';
            }
        }

        // ---- Staff eligibility — the same tests candidateStaff() applies. --
        if ($staff !== null) {
            $staff->loadMissing(['services', 'schedules']);

            if (! $staff->is_active || ! $staff->is_bookable) {
                return 'staff member is not bookable';
            }

            if (! $staff->canPerform($service)) {
                return 'staff member cannot perform this service';
            }

            if ($staff->branch_id !== null && (int) $staff->branch_id !== (int) $branch->id) {
                return 'staff member works at a different branch';
            }
        }

        // ---- Working windows must CONTAIN the whole range. -----------------
        // The previous local day participates too: a Saturday 01:00 booking
        // belongs to Friday's 20:00-02:00 shift, and judging it against
        // Saturday's windows alone would wrongly refuse it.
        $branch->loadMissing('schedules');

        $range = new TimeRange($startsAt, $endsAt);
        $windows = [];

        foreach ([$localDay->subDay(), $localDay] as $day) {
            $branchDay = $this->branchWindows($branch, $day, $timezone);

            $windows = array_merge(
                $windows,
                $staff !== null
                    ? $this->staffWindows($staff, $day, $timezone, $branchDay)
                    : $branchDay,
            );
        }

        $contained = false;

        foreach (TimeRange::merge($windows) as $window) {
            if ($window->contains($range)) {
                $contained = true;
                break;
            }
        }

        if (! $contained) {
            return 'outside working hours';
        }

        // ---- Time off — exact overlap, so no day-boundary blind spots. -----
        $blocked = TimeOff::query()
            ->where(function ($query) use ($staff, $branch): void {
                $query->where('branch_id', $branch->id);

                if ($staff !== null) {
                    $query->orWhere('staff_id', $staff->id);
                }
            })
            ->where('starts_at', '<', $endsAt)
            ->where('ends_at', '>', $startsAt)
            ->exists();

        if ($blocked) {
            return 'blocked by time off';
        }

        return null;
    }

    /**
     * Authoritative re-check, called INSIDE the booking transaction under a row
     * lock (§6.3). This is what actually prevents double-booking; slotsFor() is
     * only a display concern.
     */
    public function isStillFree(
        ?Staff $staff,
        Branch $branch,
        CarbonImmutable $startsAt,
        CarbonImmutable $endsAt,
        ?int $ignoreBookingId = null,
    ): bool {
        /*
         * Normalise to UTC before comparing.
         *
         * Callers reason in the store's local time ("15:00 on Sunday"), but
         * starts_at/ends_at are stored UTC. Comparing a +03:00 Carbon against
         * UTC columns silently shifts every comparison by three hours and the
         * conflict check finds nothing — the exact failure mode that lets two
         * customers book the same chair.
         */
        $startsAt = $startsAt->utc();
        $endsAt = $endsAt->utc();

        $query = Booking::query()
            ->blocking()
            ->overlapping(
                $startsAt->subMinutes($branch->buffer_before_minutes),
                $endsAt->addMinutes($branch->buffer_after_minutes),
            );

        // Rescheduling must not collide with the booking being moved.
        if ($ignoreBookingId !== null) {
            $query->whereKeyNot($ignoreBookingId);
        }

        if ($staff !== null) {
            $query->where('staff_id', $staff->id);
        } else {
            $query->where('branch_id', $branch->id)->whereNull('staff_id');
        }

        return ! $query->exists();
    }

    public function assigner(): StaffAssigner
    {
        return $this->staffAssigner;
    }
}
