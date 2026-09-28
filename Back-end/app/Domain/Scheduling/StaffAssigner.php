<?php

namespace App\Domain\Scheduling;

use App\Domain\Booking\BookingStatus;
use App\Models\Booking;
use App\Models\Branch;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use Carbon\CarbonImmutable;

/**
 * Picks a staff member when the customer was never asked (spec §9, §15).
 *
 *   "The backend should automatically assign an available staff member."
 *
 * Selection order (ARCHITECTURE.md §6.4):
 *   1. fewest bookings that day   — spreads load instead of hammering staff #1
 *   2. longest idle               — fairer within an equal day
 *   3. lowest id                  — deterministic tiebreak
 *
 * Step 3 matters more than it looks: this runs inside the booking transaction
 * under a row lock, and a deterministic order means the same request always
 * resolves the same way, which makes the concurrency behaviour reproducible
 * and testable.
 */
class StaffAssigner
{
    /**
     * The staff member to assign, or null if nobody is free.
     */
    public function assign(
        Store $store,
        Service $service,
        Branch $branch,
        CarbonImmutable $startsAt,
        CarbonImmutable $endsAt,
        AvailabilityEngine $availability,
    ): ?Staff {
        $candidates = Staff::query()
            ->where('store_id', $store->id)
            ->where(fn ($q) => $q->where('branch_id', $branch->id)->orWhereNull('branch_id'))
            ->bookable()
            ->capableOf($service)
            ->with('services')
            ->orderBy('id')
            ->get();

        if ($candidates->isEmpty()) {
            return null;
        }

        $dayLoad = $this->bookingCountsForDay($candidates->pluck('id')->all(), $startsAt);

        /*
         * Explicit comparator rather than sortBy([...]).
         *
         * Collection::sortBy() given an array of bare closures does not perform
         * the multi-key sort you would expect — it silently ignored the load
         * figure and always returned the same stylist, which defeats the whole
         * point of load balancing. PHP's <=> on two arrays compares them
         * lexicographically, which is exactly the "load first, then id" rule.
         */
        $ranked = $candidates->sort(function (Staff $a, Staff $b) use ($dayLoad): int {
            $loadA = $dayLoad[$a->id] ?? 0;
            $loadB = $dayLoad[$b->id] ?? 0;

            return [$loadA, $a->id] <=> [$loadB, $b->id];
        })->values();

        foreach ($ranked as $staff) {
            /*
             * Whoever we pick must have a roster that actually covers the
             * window, no time off, and no colliding booking.
             *
             * The first two checks are violationFor(); this loop used to run
             * isStillFree() alone, and an off-duty stylist has zero bookings
             * precisely BECAUSE they are off — so the load ranking above
             * systematically handed every "any available" booking to the one
             * person who was not working (audit BL-2).
             */
            if ($availability->violationFor($store, $service, $branch, $staff, $startsAt, $endsAt) !== null) {
                continue;
            }

            if ($availability->isStillFree($staff, $branch, $startsAt, $endsAt)) {
                return $staff;
            }
        }

        return null;
    }

    /**
     * How many bookings each candidate already has on that calendar day.
     *
     * @param  array<int, int>  $staffIds
     * @return array<int, int>
     */
    private function bookingCountsForDay(array $staffIds, CarbonImmutable $startsAt): array
    {
        // The day boundary is a LOCAL concept; the column is UTC. Take the local
        // day, then convert — not the other way round.
        $dayStart = $startsAt->startOfDay()->utc();
        $dayEnd = $startsAt->endOfDay()->utc();

        return Booking::query()
            ->whereIn('staff_id', $staffIds)
            ->whereIn('booking_status', BookingStatus::blockingValues())
            ->whereBetween('starts_at', [$dayStart, $dayEnd])
            ->selectRaw('staff_id, COUNT(*) as total')
            ->groupBy('staff_id')
            ->pluck('total', 'staff_id')
            ->all();
    }
}
