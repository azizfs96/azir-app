<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A pop-up ad shown to customers entering this store in the app (image +
 * optional title, scheduled, with a per-customer display frequency).
 */
#[Fillable(['store_id', 'image_path', 'title_ar', 'title_en', 'frequency', 'starts_at', 'ends_at', 'is_active', 'sort_order'])]
class StorePopup extends Model
{
    use BelongsToTenant;

    public const FREQUENCIES = ['every_visit', 'once_per_day', 'once'];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'sort_order' => 'integer',
            'starts_at' => 'immutable_datetime',
            'ends_at' => 'immutable_datetime',
        ];
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    /**
     * What a customer may see right now: switched on, has an image, and inside
     * its schedule (an unset bound is open-ended).
     *
     * @param  Builder<StorePopup>  $query
     * @return Builder<StorePopup>
     */
    public function scopeLive(Builder $query): Builder
    {
        $now = CarbonImmutable::now();

        return $query
            ->where('is_active', true)
            ->whereNotNull('image_path')
            ->where(fn ($q) => $q->whereNull('starts_at')->orWhere('starts_at', '<=', $now))
            ->where(fn ($q) => $q->whereNull('ends_at')->orWhere('ends_at', '>=', $now))
            ->orderBy('sort_order')
            ->orderBy('id');
    }

    public function displayTitle(string $locale = 'ar'): ?string
    {
        return $locale === 'en' ? ($this->title_en ?: $this->title_ar) : ($this->title_ar ?: $this->title_en);
    }
}
