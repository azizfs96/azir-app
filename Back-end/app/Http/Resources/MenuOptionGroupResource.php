<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** One option group with its options, localized (RestaurantEngine). */
class MenuOptionGroupResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $locale = app()->getLocale();

        return [
            'id' => $this->id,
            'name' => $this->displayName($locale),
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'min_select' => $this->min_select,
            'max_select' => $this->max_select,
            'required' => $this->isRequired(),
            'options' => $this->options->map(fn ($option) => [
                'id' => $option->id,
                'name' => $option->displayName($locale),
                'name_ar' => $option->name_ar,
                'name_en' => $option->name_en,
                'price_delta' => (float) $option->price_delta,
                'is_available' => $option->is_available,
            ])->values(),
        ];
    }
}
