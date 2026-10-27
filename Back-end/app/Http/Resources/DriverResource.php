<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin \App\Models\Driver */
class DriverResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'phone' => $this->phone,
            'vehicle' => $this->vehicle,
            'is_active' => $this->is_active,
            'last_location' => $this->last_located_at !== null && $this->last_latitude !== null ? [
                'latitude' => (float) $this->last_latitude,
                'longitude' => (float) $this->last_longitude,
                'heading' => $this->last_heading,
                'located_at' => $this->last_located_at->toIso8601String(),
                'fresh' => $this->hasFreshLocation(),
            ] : null,
            'active_orders_count' => $this->whenCounted('orders'),
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
