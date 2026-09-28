<?php

namespace App\Policies;

use App\Models\Merchant;
use App\Models\User;

/**
 * The tenant root itself (ARCHITECTURE.md §4).
 *
 * Merchant is not a tenant-owned resource — it IS the tenant — so the rule is
 * identity rather than ownership: a merchant user may only ever read or edit
 * the merchant record they belong to.
 */
class MerchantPolicy
{
    /**
     * Admins manage every merchant (spec §39). Granted before any other check.
     */
    public function before(User $user, string $ability): ?bool
    {
        return $user->isAdmin() ? true : null;
    }

    public function view(User $user, Merchant $merchant): bool
    {
        return $user->merchant_id === $merchant->id;
    }

    /**
     * Only the OWNER edits business details — merchant_staff must not be able
     * to change the VAT number or contact details.
     */
    public function update(User $user, Merchant $merchant): bool
    {
        return $user->isMerchantOwner() && $user->merchant_id === $merchant->id;
    }

    /** Approval and suspension are admin-only (spec §39). */
    public function approve(User $user): bool
    {
        return false;
    }

    public function suspend(User $user): bool
    {
        return false;
    }
}
