<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** One dish, localized for the requesting client (RestaurantEngine). */
class MenuItemResource extends JsonResource
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
            'calories' => $this->calories,
            'category_id' => $this->menu_category_id,
            'is_available' => $this->is_available,
            'is_active' => $this->is_active,
            'is_featured' => $this->is_featured,
            'sort_order' => $this->sort_order,
            'option_groups' => MenuOptionGroupResource::collection(
                $this->whenLoaded('optionGroups'),
            ),
        ];
    }
}
