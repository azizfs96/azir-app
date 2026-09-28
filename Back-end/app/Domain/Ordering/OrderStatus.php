<?php

namespace App\Domain\Ordering;

/**
 * The restaurant order state machine (RestaurantEngine, R3).
 *
 *                     ┌──────────────► rejected (terminal)
 *                     │
 *   placed ───► accepted ───► preparing ───► ready ───► completed (terminal)
 *     │            │              │
 *     └── cancelled┴──────────────┴────────► cancelled (terminal)
 *
 * Validated in the domain like BookingStatus — every path (customer API,
 * merchant dashboard, auto-accept, a future scheduler) is guarded identically.
 */
enum OrderStatus: string
{
    case Placed = 'placed';
    case Accepted = 'accepted';
    case Preparing = 'preparing';
    case Ready = 'ready';
    case Completed = 'completed';
    case Rejected = 'rejected';
    case Cancelled = 'cancelled';

    /** @return array<int, OrderStatus> */
    public function allowedTransitions(): array
    {
        return match ($this) {
            self::Placed => [self::Accepted, self::Rejected, self::Cancelled],
            self::Accepted => [self::Preparing, self::Ready, self::Cancelled],
            self::Preparing => [self::Ready, self::Cancelled],
            self::Ready => [self::Completed],
            self::Completed, self::Rejected, self::Cancelled => [],
        };
    }

    public function canTransitionTo(self $target): bool
    {
        return in_array($target, $this->allowedTransitions(), true);
    }

    public function isTerminal(): bool
    {
        return $this->allowedTransitions() === [];
    }

    /**
     * May the CUSTOMER cancel from here? Only before the kitchen commits —
     * once accepted, cancelling is the restaurant's call.
     */
    public function isCustomerCancellable(): bool
    {
        return $this === self::Placed;
    }
}
