<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A merchant's delivery driver: a tenant-owned profile (name, phone, vehicle,
 * last known position) backed by a `users` login with role `driver`.
 */
#[Fillable(['store_id', 'user_id', 'name', 'phone', 'vehicle', 'is_active'])]
class Driver extends Model
{
    use BelongsToTenant;

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'last_latitude' => 'decimal:8',
            'last_longitude' => 'decimal:8',
            'last_heading' => 'integer',
            'last_speed_kmh' => 'decimal:2',
            'last_located_at' => 'immutable_datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    public function orders(): HasMany
    {
        return $this->hasMany(Order::class);
    }

    /** @param  Builder<Driver>  $query */
    public function scopeActive(Builder $query): Builder
    {
        return $query->where('is_active', true);
    }

    /** A position older than this is stale — the app may have been closed. */
    public function hasFreshLocation(int $maxAgeSeconds = 180): bool
    {
        return $this->last_located_at !== null
            && $this->last_latitude !== null
            && $this->last_located_at->diffInSeconds(now()) <= $maxAgeSeconds;
    }
}
