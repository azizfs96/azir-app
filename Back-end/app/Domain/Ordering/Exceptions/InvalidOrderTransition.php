<?php

namespace App\Domain\Ordering\Exceptions;

use App\Domain\Ordering\OrderStatus;
use RuntimeException;

class InvalidOrderTransition extends RuntimeException
{
    public function __construct(OrderStatus $from, OrderStatus $to)
    {
        parent::__construct("Cannot move an order from {$from->value} to {$to->value}.");
    }
}
