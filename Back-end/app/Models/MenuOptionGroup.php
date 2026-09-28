<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A question the customer answers about a dish — الحجم، الإضافات، الصوصات.
 *
 * min/max selections encode every Jahez pattern:
 *   min 1 / max 1  → required single choice (size)
 *   min 0 / max 5  → optional extras
 *   min 2 / max 2  → "choose exactly two sauces"
 */
#[Fillable(['store_id', 'menu_item_id', 'name_ar', 'name_en', 'min_select', 'max_select', 'sort_order'])]
class MenuOptionGroup extends Model
{
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return [
            'min_select' => 'integer',
            'max_select' => 'integer',
            'sort_order' => 'integer',
        ];
    }

    public function item(): BelongsTo
    {
        return $this->belongsTo(MenuItem::class, 'menu_item_id');
    }

    public function options(): HasMany
    {
        return $this->hasMany(MenuOption::class)->orderBy('sort_order')->orderBy('id');
    }

    public function isRequired(): bool
    {
        return $this->min_select > 0;
    }

    public function displayName(string $locale = 'ar'): string
    {
        return $locale === 'en' ? ($this->name_en ?: $this->name_ar) : $this->name_ar;
    }
}
