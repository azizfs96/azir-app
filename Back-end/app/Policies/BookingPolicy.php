<?php

namespace App\Policies;

/**
 * Tenant isolation for Booking (ARCHITECTURE.md §4).
 * All rules inherited from TenantOwnedPolicy: a merchant user may only touch
 * rows whose merchant_id matches their own.
 */
class BookingPolicy extends TenantOwnedPolicy
{
}
