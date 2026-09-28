<?php

namespace App\Domain\Concerns;

use App\Models\Merchant;
use App\Support\TenantContext;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Scope;
use Illuminate\Database\Eloquent\Model;

/**
 * Layer 2 of tenant isolation (ARCHITECTURE.md §4).
 *
 * Applied to every model that carries merchant_id. It does two things:
 *
 *   1. Adds a global `where merchant_id = ?` scope, so a query that FORGETS to
 *      filter still cannot leak another merchant's rows. This is the safety net
 *      beneath the policies, not a replacement for them.
 *
 *   2. Auto-fills merchant_id on create, so application code never has to pass
 *      it — and therefore can never pass the wrong one.
 *
 * Layer 1 is deriving the tenant from the authenticated user only (TenantContext).
 * Layer 3 is per-model policies. Defence in depth: any one layer failing is not
 * a breach.
 */
trait BelongsToTenant
{
    public static function bootBelongsToTenant(): void
    {
        static::addGlobalScope(new TenantScope);

        static::creating(function (Model $model): void {
            if ($model->getAttribute('merchant_id') !== null) {
                return;
            }

            $tenant = app(TenantContext::class);

            if ($tenant->hasTenant()) {
                $model->setAttribute('merchant_id', $tenant->id());
            }
        });
    }

    public function merchant(): BelongsTo
    {
        return $this->belongsTo(Merchant::class);
    }

    /**
     * Create a tenant-owned row with merchant_id taken from trusted server-side
     * data rather than from ambient tenant context.
     *
     * `merchant_id` is deliberately absent from every model's $fillable so no
     * request payload can reach it — which also means mass assignment cannot
     * set it legitimately. Several paths need to: public QR scans and customer
     * bookings run with NO tenant context at all, and seeders/jobs run outside
     * a request. They all know the owning merchant from a resolved Store, so
     * this stamps it explicitly instead of each call site reinventing forceFill.
     *
     * @param  array<string, mixed>  $attributes
     */
    public static function createOwnedBy(int|Merchant $merchant, array $attributes): static
    {
        $model = new static($attributes);

        $model->forceFill([
            'merchant_id' => $merchant instanceof Merchant ? $merchant->id : $merchant,
        ])->save();

        return $model;
    }

    /**
     * Escape hatch for admin queries and jobs. Deliberately verbose to read —
     * every call site should be obvious in review.
     *
     * @param  Builder<covariant Model>  $query
     */
    public function scopeWithoutTenancy(Builder $query): Builder
    {
        return $query->withoutGlobalScope(TenantScope::class);
    }

    /**
     * Explicitly query one tenant regardless of ambient context.
     *
     * @param  Builder<covariant Model>  $query
     */
    public function scopeForMerchant(Builder $query, int|Merchant $merchant): Builder
    {
        $id = $merchant instanceof Merchant ? $merchant->id : $merchant;

        return $query->withoutGlobalScope(TenantScope::class)
            ->where($query->getModel()->qualifyColumn('merchant_id'), $id);
    }
}

/**
 * The global scope itself.
 *
 * Note it only applies when a tenant is actually resolved. Unauthenticated
 * public routes (store resolution by public_token) and the admin panel run with
 * no tenant, and are protected by their own explicit constraints instead.
 */
class TenantScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        $tenant = app(TenantContext::class);

        if (! $tenant->shouldScope()) {
            return;
        }

        $builder->where($model->qualifyColumn('merchant_id'), $tenant->id());
    }
}
