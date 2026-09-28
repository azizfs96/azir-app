<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** A bookable service, localized for the requesting client (spec §14, §33). */
class ServiceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $locale = app()->getLocale();

        return [
            'id' => $this->id,
            'name' => $this->displayName($locale),
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'description' => $locale === 'en'
                ? ($this->description_en ?: $this->description_ar)
                : $this->description_ar,
            'image' => $this->image_path,
            'price' => (float) $this->price,
            'currency' => $this->currency,
            'duration_minutes' => $this->duration_minutes,
            'category_id' => $this->service_category_id,
        ];
    }
}
