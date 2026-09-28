<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A customer belongs to the PLATFORM, not to any merchant (ARCHITECTURE.md §5.2).
 *
 * One identity across every store they have scanned — that is the entire point
 * of "one customer app, many merchants". Deliberately NOT tenant-scoped.
 */
#[Fillable(['user_id', 'first_name', 'last_name', 'gender', 'date_of_birth', 'marketing_opt_in'])]
class Customer extends Model
{
    use HasFactory;

    protected function casts(): array
    {
        return [
            'date_of_birth' => 'date',
            'marketing_opt_in' => 'boolean',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * "My Stores" — the ONLY discovery surface in the product (spec §5, §46).
     *
     * There is no counterpart relation that returns stores the customer has not
     * added, and none should ever be written.
     */
    public function stores(): BelongsToMany
    {
        return $this->belongsToMany(Store::class, 'customer_stores')
            ->withPivot(['added_via', 'first_added_at', 'last_visited_at', 'last_booking_at', 'is_hidden'])
            ->withTimestamps();
    }

    public function customerStores(): HasMany
    {
        return $this->hasMany(CustomerStore::class);
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }

    /**
     * Saved delivery addresses — managed once in the app, reused at every store
     * (feature expansion). A store never sees these directly; it receives only
     * the one address the customer picks at checkout, snapshotted onto the order.
     */
    public function addresses(): HasMany
    {
        return $this->hasMany(CustomerAddress::class);
    }

    /** The address a delivery defaults to when the customer picks none. */
    public function defaultAddress(): ?CustomerAddress
    {
        return $this->addresses()
            ->orderByDesc('is_default')
            ->orderByDesc('id')
            ->first();
    }

    /** Saved cars for curbside pickup (feature expansion), central like addresses. */
    public function cars(): HasMany
    {
        return $this->hasMany(CustomerCar::class);
    }

    public function fullName(): string
    {
        return trim(($this->first_name ?? '').' '.($this->last_name ?? '')) ?: $this->user->name;
    }
}
