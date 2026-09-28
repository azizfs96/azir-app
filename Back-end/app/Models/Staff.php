<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/** Staff member — optional per spec §15. */
#[Fillable([
    'store_id', 'branch_id', 'user_id', 'name', 'title_ar', 'title_en',
    'avatar_path', 'gender', 'bio', 'is_active', 'is_bookable', 'sort_order',
])]
class Staff extends Model
{
    use BelongsToTenant, HasFactory, SoftDeletes;

    protected $table = 'staff';

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'is_bookable' => 'boolean',
        ];
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function services(): BelongsToMany
    {
        return $this->belongsToMany(Service::class, 'staff_services')
            ->withPivot(['duration_override_minutes', 'price_override'])
            ->withTimestamps();
    }

    public function schedules(): HasMany
    {
        return $this->hasMany(StaffSchedule::class);
    }

    public function timeOff(): HasMany
    {
        return $this->hasMany(TimeOff::class);
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }

    /**
     * Can this staff member perform this service?
     *
     * ========================================================================
     * THE spec §15 RULE:
     *   "If no specific services are assigned to a staff member, assume they
     *    can perform all services."
     *
     * So an EMPTY assignment list means unrestricted, not unqualified. Getting
     * this backwards would make every zero-setup merchant unbookable.
     * ========================================================================
     */
    public function canPerform(Service $service): bool
    {
        $assigned = $this->relationLoaded('services')
            ? $this->services
            : $this->services()->get();

        if ($assigned->isEmpty()) {
            return true;
        }

        return $assigned->contains('id', $service->id);
    }

    /**
     * Staff eligible for a service: either unrestricted (no assignments) or
     * explicitly assigned to it.
     *
     * @param  Builder<Staff>  $query
     */
    public function scopeCapableOf(Builder $query, Service $service): Builder
    {
        return $query->where(function (Builder $q) use ($service): void {
            $q->whereDoesntHave('services')
                ->orWhereHas('services', fn (Builder $s) => $s->whereKey($service->id));
        });
    }

    /** @param  Builder<Staff>  $query */
    public function scopeBookable(Builder $query): Builder
    {
        return $query->where('is_active', true)->where('is_bookable', true);
    }

    /**
     * Duration this specific staff member takes for a service, honouring any
     * per-staff override.
     */
    public function durationFor(Service $service): int
    {
        $override = $this->services->firstWhere('id', $service->id)
            ?->pivot?->duration_override_minutes;

        return $override ?? $service->duration_minutes;
    }
}
