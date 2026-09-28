<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A branch. Coordinates are here so the customer can find the place AFTER
 * booking — there is no proximity search anywhere in Wasla (§46).
 */
class BranchResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->displayName(app()->getLocale()),
            'address' => $this->address_line,
            'city' => $this->city,
            'latitude' => $this->latitude !== null ? (float) $this->latitude : null,
            'longitude' => $this->longitude !== null ? (float) $this->longitude : null,
            'phone' => $this->phone,
            'google_maps_url' => $this->google_maps_url,
        ];
    }
}
