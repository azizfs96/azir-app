<?php

namespace App\Domain\Ordering\Events;

use App\Domain\Ordering\OrderStatus;
use App\Models\Order;
use Illuminate\Foundation\Events\Dispatchable;

/**
 * Announced on every order status change (including creation). The ordering
 * engine knows nothing about notifications — a listener turns this into the
 * customer's "order accepted / ready" message, exactly as bookings do (§23).
 */
class OrderStatusChanged
{
    use Dispatchable;

    public function __construct(
        public readonly Order $order,
        public readonly ?OrderStatus $from,
        public readonly OrderStatus $to,
        public readonly string $actorType,
    ) {}
}
