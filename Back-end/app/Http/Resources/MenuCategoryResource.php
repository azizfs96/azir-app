<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** One menu section with its dishes (RestaurantEngine). */
class MenuCategoryResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $locale = app()->getLocale();

        return [
            'id' => $this->id,
            'name' => $this->displayName($locale),
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'image' => $this->image_path,
            'sort_order' => $this->sort_order,
            'is_active' => $this->is_active,
            'items' => MenuItemResource::collection($this->whenLoaded('items')),
        ];
    }
}
