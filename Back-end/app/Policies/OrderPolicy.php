<?php

namespace App\Policies;

/**
 * Tenant isolation for orders (ARCHITECTURE.md §4). A merchant user may only
 * touch orders whose merchant_id matches their own.
 */
class OrderPolicy extends TenantOwnedPolicy
{
}
