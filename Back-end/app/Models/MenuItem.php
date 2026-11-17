<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * One orderable dish (RestaurantEngine).
 *
 * `is_active` is menu curation (does it belong on the menu at all);
 * `is_available` is the live sold-out switch flipped during service.
 * A customer can order it only when BOTH are true — the distinction exists so
 * that "sold out tonight" never means "re-enter the whole dish tomorrow".
 */
#[Fillable([
    'store_id', 'menu_category_id', 'name_ar', 'name_en', 'description_ar',
    'description_en', 'price', 'compare_at_price', 'unit', 'stock_quantity', 'calories', 'image_path',
    'is_available', 'is_featured', 'is_active', 'sort_order',
])]
class MenuItem extends Model
{
    use BelongsToTenant, HasFactory, SoftDeletes;

    protected function casts(): array
    {
        return [
            'price' => 'decimal:2',
            'compare_at_price' => 'decimal:2',
            'stock_quantity' => 'integer',
            'calories' => 'integer',
            'is_available' => 'boolean',
            'is_active' => 'boolean',
            'is_featured' => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(MenuCategory::class, 'menu_category_id');
    }

    public function optionGroups(): HasMany
    {
        return $this->hasMany(MenuOptionGroup::class)->orderBy('sort_order')->orderBy('id');
    }

    /** A tracked product at zero is sold out; untracked (null) never is. */
    public function inStock(): bool
    {
        return $this->stock_quantity === null || $this->stock_quantity > 0;
    }

    /** Whole-percent saving from the compare-at price, or null without one. */
    public function discountPercent(): ?int
    {
        $was = (float) ($this->compare_at_price ?? 0);
        $now = (float) $this->price;
        if ($was <= 0 || $was <= $now) {
            return null;
        }

        return (int) round(($was - $now) / $was * 100);
    }

    public function isOrderable(): bool
    {
        return $this->is_active && $this->is_available && $this->deleted_at === null;
    }

    public function displayName(string $locale = 'ar'): string
    {
        return $locale === 'en' ? ($this->name_en ?: $this->name_ar) : $this->name_ar;
    }
}
