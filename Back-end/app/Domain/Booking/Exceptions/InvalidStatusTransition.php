<?php

namespace App\Domain\Booking\Exceptions;

use App\Domain\Booking\BookingStatus;
use DomainException;

/**
 * Thrown when something attempts a transition the state machine forbids
 * (spec §19). Rendered as HTTP 422 with error_code INVALID_STATUS_TRANSITION.
 */
class InvalidStatusTransition extends DomainException
{
    public function __construct(
        public readonly BookingStatus $from,
        public readonly BookingStatus $to,
    ) {
        parent::__construct(
            "Cannot transition a booking from [{$from->value}] to [{$to->value}]."
        );
    }

    public function errorCode(): string
    {
        return 'INVALID_STATUS_TRANSITION';
    }
}
