<?php

namespace App\Listeners;

use App\Domain\Booking\BookingStatus;
use App\Domain\Booking\Events\BookingRescheduled;
use App\Domain\Booking\Events\BookingStatusChanged;
use App\Domain\Notification\NotificationDispatcher;
use Illuminate\Contracts\Queue\ShouldQueue;

/**
 * Turns booking events into customer notifications (spec §23).
 *
 * NOTE the method names: Laravel auto-discovers listener methods called
 * handle*() that type-hint an event. Since these are ALSO registered explicitly
 * in AppServiceProvider, a handle* name would register them twice and send
 * every notification twice. on*() keeps the explicit wiring authoritative.
 *
 * Queued: a slow push provider must never make the booking request slow. The
 * customer's confirmation screen should not wait on Firebase.
 */
class SendBookingNotification implements ShouldQueue
{
    public function __construct(private readonly NotificationDispatcher $dispatcher) {}

    public function onStatusChanged(BookingStatusChanged $event): void
    {
        // Only these transitions are worth interrupting someone for. Notifying
        // on every state change (checked_in, for instance) would train people
        // to ignore Wasla notifications entirely.
        $template = match ($event->to) {
            BookingStatus::Confirmed => 'booking_confirmed',
            BookingStatus::Cancelled => 'booking_cancelled',
            BookingStatus::Completed => 'booking_completed',
            default => null,
        };

        if ($template === null) {
            return;
        }

        $this->dispatcher->bookingEvent($event->booking, $template);
    }

    public function onRescheduled(BookingRescheduled $event): void
    {
        $this->dispatcher->bookingEvent($event->booking, 'booking_rescheduled');
    }
}
