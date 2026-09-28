<?php

namespace App\Models;

use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

/**
 * Deferred deep-link claim (spec §7 / ARCHITECTURE.md §8.3).
 * Short-lived by design: match reliability decays, and this is fingerprint data.
 */
#[Fillable([
    'store_public_token', 'fingerprint_hash', 'platform', 'ip_hash',
    'user_agent', 'expires_at',
])]
class DeepLinkAttribution extends Model
{
    protected function casts(): array
    {
        return [
            'expires_at' => 'immutable_datetime',
            'claimed_at' => 'immutable_datetime',
        ];
    }

    /** @param Builder<DeepLinkAttribution> $query */
    public function scopeClaimable(Builder $query): Builder
    {
        return $query->whereNull('claimed_by_customer_id')
            ->where('expires_at', '>', CarbonImmutable::now());
    }
}
