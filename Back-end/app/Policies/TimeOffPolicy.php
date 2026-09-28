<?php

namespace App\Policies;

/**
 * Tenant isolation for TimeOff (ARCHITECTURE.md §4).
 * All rules inherited from TenantOwnedPolicy: a merchant user may only touch
 * rows whose merchant_id matches their own.
 */
class TimeOffPolicy extends TenantOwnedPolicy
{
}
