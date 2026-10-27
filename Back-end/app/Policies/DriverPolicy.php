<?php

namespace App\Policies;

/**
 * All rules inherited from TenantOwnedPolicy: a merchant user may only touch
 * drivers that belong to their own merchant.
 */
class DriverPolicy extends TenantOwnedPolicy {}
