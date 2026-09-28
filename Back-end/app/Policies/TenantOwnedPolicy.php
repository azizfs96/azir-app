<?php

namespace App\Policies;

use App\Models\User;
use Illuminate\Database\Eloquent\Model;

/**
 * Layer 3 of tenant isolation (ARCHITECTURE.md §4).
 *
 * Base policy for every merchant-owned resource. The rule is always the same,
 * so it is written once: the acting user must be a merchant user, and the
 * record's merchant_id must equal THEIR merchant_id.
 *
 * Note this compares against $user->merchant_id — the authenticated user's own
 * column — not against anything supplied by the request (spec §35).
 *
 * A denial surfaces as HTTP 404, not 403 (see bootstrap/app.php), so one
 * merchant cannot probe another's id space.
 */
abstract class TenantOwnedPolicy
{
    /**
     * Which model attribute holds the tenant id. Always merchant_id here, but
     * kept overridable for resources reached through a parent.
     */
    protected string $tenantColumn = 'merchant_id';

    public function viewAny(User $user): bool
    {
        return $this->actsWithinTenant($user);
    }

    public function view(User $user, Model $model): bool
    {
        return $this->owns($user, $model);
    }

    public function create(User $user): bool
    {
        return $this->actsWithinTenant($user);
    }

    public function update(User $user, Model $model): bool
    {
        return $this->owns($user, $model);
    }

    public function delete(User $user, Model $model): bool
    {
        return $this->owns($user, $model);
    }

    /**
     * The single ownership test every rule above funnels through.
     */
    protected function owns(User $user, Model $model): bool
    {
        if (! $this->actsWithinTenant($user)) {
            return false;
        }

        $modelTenantId = $model->getAttribute($this->tenantColumn);

        // A record with no tenant is never merchant-owned data; refuse rather
        // than let a null == null comparison pass.
        if ($modelTenantId === null) {
            return false;
        }

        return (int) $modelTenantId === (int) $user->merchant_id;
    }

    protected function actsWithinTenant(User $user): bool
    {
        return $user->isMerchantUser()
            && $user->merchant_id !== null
            && $user->is_active;
    }
}
