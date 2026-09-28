<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** Service grouping within one store — never a cross-merchant taxonomy (§46). */
class ServiceCategoryResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->displayName(app()->getLocale()),
            'icon' => $this->icon,
            'services' => ServiceResource::collection($this->whenLoaded('services')),
        ];
    }
}
