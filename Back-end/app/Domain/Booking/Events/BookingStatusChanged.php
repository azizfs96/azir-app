<?php

namespace App\Domain\Booking\Events;

use App\Domain\Booking\BookingStatus;
use App\Models\Booking;
use Illuminate\Foundation\Events\Dispatchable;

/**
 * Emitted on every state transition (spec §19, §23).
 *
 * The booking engine fires this and moves on. Whether that results in a push,
 * an email, or nothing at all is entirely the notification layer's business —
 * which is what lets WhatsApp be added later without touching booking code.
 */
class BookingStatusChanged
{
    use Dispatchable;

    public function __construct(
        public readonly Booking $booking,
        public readonly ?BookingStatus $from,
        public readonly BookingStatus $to,
        public readonly string $actorType,
    ) {}
}
