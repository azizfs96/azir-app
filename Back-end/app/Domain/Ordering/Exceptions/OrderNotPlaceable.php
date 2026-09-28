<?php

namespace App\Domain\Ordering\Exceptions;

use RuntimeException;

/**
 * The order cannot be created as submitted — an empty cart, an unavailable
 * dish, an option that does not belong to the item, or a group's min/max
 * selection rule broken. Carries a stable code the API maps to an error_code.
 */
class OrderNotPlaceable extends RuntimeException
{
    public function __construct(public readonly string $errorCode, string $message)
    {
        parent::__construct($message);
    }
}
