<?php

namespace App\Observers;

use App\Domain\Scheduling\AvailabilityCache;
use App\Models\Booking;
use Illuminate\Contracts\Events\ShouldHandleEventsAfterCommit;

/**
 * ============================================================================
 * KEEP THE AVAILABILITY CACHE HONEST AFTER A BOOKING CHANGES (C-2)
 *
 * ShouldHandleEventsAfterCommit is the whole point of doing this here rather
 * than inside BookingService: these methods run only once the surrounding
 * transaction has COMMITTED. A booking that rolls back — a lost slot race, a
 * failed insert — never reaches this class, so a failure cannot evict a cache
 * entry that is still perfectly accurate.
 *
 * Observing the MODEL also means every path is covered by one hook: customer
 * bookings, merchant dashboard status changes, cancellations, reschedules and
 * anything added later. Wiring each call site individually would leave the next
 * one to be forgotten.
 * ============================================================================
 */
class BookingAvailabilityObserver implements ShouldHandleEventsAfterCommit
{
    public function __construct(private readonly AvailabilityCache $cache) {}

    public function created(Booking $booking): void
    {
        $this->invalidate($booking);
    }

    /**
     * Covers cancellation, no-show, completion and rescheduling.
     *
     * A status change frees or occupies the slot; a reschedule moves it. Both
     * are updates, and both make previously cached slot lists wrong.
     */
    public function updated(Booking $booking): void
    {
        $this->invalidate($booking);

        /*
         * If the booking moved to a DIFFERENT stylist, the one it left behind
         * has just gained free time. Their cache must be bumped too, or the
         * vacated slot stays hidden until the TTL expires.
         */
        $previousStaffId = $booking->getOriginal('staff_id');

        if ($previousStaffId !== null && $previousStaffId !== $booking->staff_id) {
            $this->cache->forgetStaff($booking->store_id, (int) $previousStaffId);
        }
    }

    /** Soft deletes release the slot as well (the engine ignores trashed rows). */
    public function deleted(Booking $booking): void
    {
        $this->invalidate($booking);
    }

    public function restored(Booking $booking): void
    {
        $this->invalidate($booking);
    }

    private function invalidate(Booking $booking): void
    {
        $this->cache->forgetStaff(
            $booking->store_id,
            $booking->staff_id !== null ? (int) $booking->staff_id : null,
        );
    }
}
