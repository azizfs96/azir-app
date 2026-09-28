<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * The tenant root (ARCHITECTURE.md §4).
 *
 * Note this model does NOT use BelongsToTenant — it IS the tenant. Access is
 * controlled by MerchantPolicy: a merchant user may only ever read their own.
 */
#[Fillable([
    'owner_user_id', 'legal_name', 'display_name', 'commercial_registration',
    'vat_number', 'contact_phone', 'contact_email', 'status', 'onboarding_step',
])]
class Merchant extends Model
{
    use HasFactory, SoftDeletes;

    public const STATUS_PENDING = 'pending';

    public const STATUS_APPROVED = 'approved';

    public const STATUS_SUSPENDED = 'suspended';

    public const STATUS_REJECTED = 'rejected';

    /** Onboarding is 9 steps (spec §11). */
    public const FINAL_ONBOARDING_STEP = 9;

    protected function casts(): array
    {
        return [
            'onboarded_at' => 'datetime',
            'approved_at' => 'datetime',
            'suspended_at' => 'datetime',
            'onboarding_step' => 'integer',
        ];
    }

    // ---- Relations ----

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'owner_user_id');
    }

    public function users(): HasMany
    {
        return $this->hasMany(User::class);
    }

    public function stores(): HasMany
    {
        return $this->hasMany(Store::class);
    }

    /**
     * The MVP ships one store per merchant; the schema allows more (§13 decision 9).
     */
    public function store(): HasOne
    {
        return $this->hasOne(Store::class);
    }

    public function branches(): HasMany
    {
        return $this->hasMany(Branch::class);
    }

    public function services(): HasMany
    {
        return $this->hasMany(Service::class);
    }

    public function staff(): HasMany
    {
        return $this->hasMany(Staff::class);
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }

    public function settings(): HasOne
    {
        return $this->hasOne(MerchantSetting::class);
    }

    // ---- State ----

    /**
     * Can this merchant transact? Both conditions matter: an approved merchant
     * that has been suspended must not take bookings.
     */
    public function isOperational(): bool
    {
        return $this->status === self::STATUS_APPROVED;
    }

    public function hasCompletedOnboarding(): bool
    {
        return $this->onboarded_at !== null;
    }

    /** @param  Builder<Merchant>  $query */
    public function scopeApproved(Builder $query): Builder
    {
        return $query->where('status', self::STATUS_APPROVED);
    }
}
