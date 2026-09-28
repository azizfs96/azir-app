<?php

namespace App\Domain\Booking;

/**
 * The booking state machine (spec §19).
 *
 *   "Do not allow arbitrary status changes. Define valid transitions."
 *
 *                   ┌──────────────► cancelled (terminal)
 *                   │                    ▲
 *   pending ───► confirmed ───► checked_in ───► completed (terminal)
 *      │             │                │
 *      │             └────────────────┴──────► no_show (terminal)
 *      └──────────► cancelled
 *
 * Transitions are validated here, in the domain — not in a controller, so every
 * path into the model (API, dashboard, queued job, seeder) is equally guarded.
 */
enum BookingStatus: string
{
    case Pending = 'pending';
    case Confirmed = 'confirmed';
    case CheckedIn = 'checked_in';
    case Completed = 'completed';
    case Cancelled = 'cancelled';
    case NoShow = 'no_show';

    /**
     * @return array<int, BookingStatus>
     */
    public function allowedTransitions(): array
    {
        return match ($this) {
            self::Pending => [self::Confirmed, self::Cancelled],
            self::Confirmed => [self::CheckedIn, self::Cancelled, self::NoShow],
            self::CheckedIn => [self::Completed, self::NoShow],

            // Terminal — a completed or cancelled booking is history.
            self::Completed, self::Cancelled, self::NoShow => [],
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
     * Does this booking still occupy its slot?
     *
     * Used by the availability engine: only these statuses block the calendar.
     * A cancelled or no-show booking releases its time (ARCHITECTURE.md §6.1).
     */
    public function blocksAvailability(): bool
    {
        return in_array($this, [self::Pending, self::Confirmed, self::CheckedIn], true);
    }

    /**
     * Statuses that occupy a slot, as raw strings for query builders.
     *
     * @return array<int, string>
     */
    public static function blockingValues(): array
    {
        return array_map(
            fn (self $status) => $status->value,
            array_filter(self::cases(), fn (self $status) => $status->blocksAvailability()),
        );
    }

    /**
     * May the CUSTOMER cancel from this state? A customer cannot cancel a
     * booking they have already been checked in to.
     */
    public function isCustomerCancellable(): bool
    {
        return in_array($this, [self::Pending, self::Confirmed], true);
    }
}
