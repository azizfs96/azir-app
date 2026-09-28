<?php

namespace App\Domain\Booking\Exceptions;

use DomainException;

/**
 * Two customers reached for the same slot and this one lost the race (§6.3).
 *
 * Rendered as HTTP 409 with error_code SLOT_TAKEN so the client can refresh
 * availability and re-prompt, rather than showing a generic failure.
 */
class SlotNoLongerAvailable extends DomainException
{
    public function errorCode(): string
    {
        return 'SLOT_TAKEN';
    }
}
