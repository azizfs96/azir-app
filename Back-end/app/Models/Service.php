<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * A bookable service (spec §14). Part of the Beauty & Wellness engine catalog.
 *
 * duration_minutes + buffer_after_minutes together define how much of a staff
 * member's day one booking consumes (ARCHITECTURE.md §6.1).
 */
#[Fillable([
    'store_id', 'service_category_id', 'name_ar', 'name_en', 'description_ar',
    'description_en', 'image_path', 'price', 'currency', 'duration_minutes',
    'buffer_after_minutes', 'is_active', 'sort_order',
])]
class Service extends Model
{
    use BelongsToTenant, HasFactory, SoftDeletes;

    protected function casts(): array
    {
        return [
            'price' => 'decimal:2',
            'duration_minutes' => 'integer',
            'buffer_after_minutes' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(ServiceCategory::class, 'service_category_id');
    }

    /**
     * Staff explicitly assigned to this service.
     *
     * CAUTION: an empty result does NOT mean "nobody can do this". Staff with no
     * staff_services rows can perform everything (spec §15) — use
     * Staff::capableOf() rather than reading this relation directly.
     */
    public function staff(): BelongsToMany
    {
        return $this->belongsToMany(Staff::class, 'staff_services')
            ->withPivot(['duration_override_minutes', 'price_override'])
            ->withTimestamps();
    }

    /**
     * Total time this service occupies, including its own cleanup buffer.
     */
    public function totalMinutes(): int
    {
        return $this->duration_minutes + $this->buffer_after_minutes;
    }

    public function displayName(string $locale = 'ar'): string
    {
        return $locale === 'en' ? ($this->name_en ?: $this->name_ar) : $this->name_ar;
    }

    /** @param  Builder<Service>  $query */
    public function scopeActive(Builder $query): Builder
    {
        return $query->where('is_active', true);
    }
}
