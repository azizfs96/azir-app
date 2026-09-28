<?php

namespace App\Listeners;

use App\Domain\Notification\NotificationDispatcher;
use App\Domain\Ordering\Events\OrderStatusChanged;
use App\Domain\Ordering\OrderStatus;
use Illuminate\Contracts\Queue\ShouldQueue;

/**
 * Turns order events into customer notifications (spec §23), exactly as
 * SendBookingNotification does for bookings.
 *
 * NOTE the on*() method name (not handle*): the listener is registered
 * explicitly in AppServiceProvider, and a handle* name would ALSO be
 * auto-discovered, sending every notification twice.
 *
 * Queued so a slow push provider never slows the merchant's "accept" tap.
 */
class SendOrderNotification implements ShouldQueue
{
    public function __construct(private readonly NotificationDispatcher $dispatcher) {}

    public function onStatusChanged(OrderStatusChanged $event): void
    {
        // Placed is skipped: the customer just tapped "order" and is looking at
        // the tracking screen. A cancel the customer made themselves is skipped
        // too — they know. Everything else is a genuine update worth a ping.
        $template = match ($event->to) {
            OrderStatus::Accepted => 'order_accepted',
            OrderStatus::Preparing => 'order_preparing',
            OrderStatus::Ready => 'order_ready',
            OrderStatus::Completed => 'order_completed',
            OrderStatus::Rejected => 'order_rejected',
            OrderStatus::Cancelled => $event->actorType === 'customer' ? null : 'order_cancelled',
            default => null,
        };

        if ($template === null) {
            return;
        }

        $this->dispatcher->orderEvent($event->order, $template);
    }
}
