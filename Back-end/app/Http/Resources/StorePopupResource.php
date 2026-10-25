<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\StorePopup */
class StorePopupResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        $locale = app()->getLocale();

        return [
            'id' => $this->id,
            'image' => $this->image_path,
            'title' => $this->displayTitle($locale),
            'title_ar' => $this->title_ar,
            'title_en' => $this->title_en,
            'frequency' => $this->frequency,
            'starts_at' => $this->starts_at?->toIso8601String(),
            'ends_at' => $this->ends_at?->toIso8601String(),
            'is_active' => $this->is_active,
            'sort_order' => $this->sort_order,
        ];
    }
}
