<?php

namespace App\Domain\Booking\Events;

use App\Models\Booking;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Events\Dispatchable;

/** Emitted when a booking moves to a new time (spec §22). */
class BookingRescheduled
{
    use Dispatchable;

    public function __construct(
        public readonly Booking $booking,
        public readonly CarbonImmutable $previousStartsAt,
    ) {}
}
