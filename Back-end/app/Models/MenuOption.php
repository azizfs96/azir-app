<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One answer inside an option group — وسط +0، جبن إضافي +3، بدون بصل +0.
 *
 * Carries a price DELTA, never a price: the item owns the base price, and the
 * order total is computed server-side from base + selected deltas (R1). The
 * client is never trusted with arithmetic.
 */
#[Fillable(['store_id', 'menu_option_group_id', 'name_ar', 'name_en', 'price_delta', 'is_available', 'sort_order'])]
class MenuOption extends Model
{
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return [
            'price_delta' => 'decimal:2',
            'is_available' => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    public function group(): BelongsTo
    {
        return $this->belongsTo(MenuOptionGroup::class, 'menu_option_group_id');
    }

    public function displayName(string $locale = 'ar'): string
    {
        return $locale === 'en' ? ($this->name_en ?: $this->name_ar) : $this->name_ar;
    }
}
