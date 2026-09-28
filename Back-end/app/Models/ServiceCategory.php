<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Grouping of services within ONE store — Hair, Nails, Facial, Massage.
 * Not a cross-merchant taxonomy; nothing browses these globally (spec §46).
 */
#[Fillable(['store_id', 'name_ar', 'name_en', 'icon', 'sort_order', 'is_active'])]
class ServiceCategory extends Model
{
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    public function services(): HasMany
    {
        return $this->hasMany(Service::class);
    }

    public function displayName(string $locale = 'ar'): string
    {
        return $locale === 'en' ? ($this->name_en ?: $this->name_ar) : $this->name_ar;
    }
}
