<?php

namespace App\Support;

use App\Models\Merchant;
use RuntimeException;

/**
 * The single source of truth for "which merchant is this request acting as".
 *
 * ============================================================================
 * SECURITY INVARIANT (spec §26, §35 / ARCHITECTURE.md §4)
 *
 *   The tenant id is derived ONCE, from the authenticated user, by the
 *   ResolveTenant middleware. It is NEVER read from a request body, query
 *   string, route parameter, or header.
 *
 *   "Never trust tenant IDs sent from the frontend."
 *
 * Nothing else in the application may call setTenant(). If a controller ever
 * needs to "switch tenant", that is a bug, not a feature.
 * ============================================================================
 *
 * Registered as a singleton, so it is request-scoped: one resolution per
 * request, and every global scope reads the same value.
 */
class TenantContext
{
    private ?Merchant $merchant = null;

    /**
     * When true, the BelongsToTenant global scope is suspended.
     * Only Admin controllers and queued jobs may do this, via withoutTenancy().
     */
    private bool $suspended = false;

    public function setTenant(?Merchant $merchant): void
    {
        $this->merchant = $merchant;
    }

    public function merchant(): ?Merchant
    {
        return $this->merchant;
    }

    public function id(): ?int
    {
        return $this->merchant?->id;
    }

    public function hasTenant(): bool
    {
        return $this->merchant !== null;
    }

    /**
     * The tenant id, or an exception. Use where a tenant is structurally
     * required, so a missing tenant fails loudly instead of silently querying
     * across every merchant on the platform.
     */
    public function idOrFail(): int
    {
        if ($this->merchant === null) {
            throw new RuntimeException(
                'No tenant resolved. A merchant-scoped operation ran outside merchant context.'
            );
        }

        return $this->merchant->id;
    }

    /**
     * Should the global scope apply right now?
     */
    public function shouldScope(): bool
    {
        return ! $this->suspended && $this->merchant !== null;
    }

    /**
     * Run a callback with tenant scoping disabled.
     *
     * Legitimate uses: the admin panel (which reports across merchants), and
     * queued jobs that operate on a booking they already resolved by id.
     * The suspension is always restored, including on exception.
     *
     * @template T
     *
     * @param  callable():T  $callback
     * @return T
     */
    public function withoutTenancy(callable $callback): mixed
    {
        $previous = $this->suspended;
        $this->suspended = true;

        try {
            return $callback();
        } finally {
            $this->suspended = $previous;
        }
    }

    /**
     * Run a callback as a specific tenant. For queued jobs, which have no
     * authenticated user but do know which merchant they belong to.
     *
     * @template T
     *
     * @param  callable():T  $callback
     * @return T
     */
    public function asTenant(Merchant $merchant, callable $callback): mixed
    {
        $previousMerchant = $this->merchant;
        $previousSuspended = $this->suspended;

        $this->merchant = $merchant;
        $this->suspended = false;

        try {
            return $callback();
        } finally {
            $this->merchant = $previousMerchant;
            $this->suspended = $previousSuspended;
        }
    }
}
