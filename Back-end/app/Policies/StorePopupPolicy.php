<?php

namespace App\Policies;

/**
 * All rules inherited from TenantOwnedPolicy: a merchant user may only touch
 * pop-ups that belong to their own merchant.
 */
class StorePopupPolicy extends TenantOwnedPolicy {}
