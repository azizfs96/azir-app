<?php

namespace App\Http\Resources;

use App\Models\CustomerCar;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @property CustomerCar $resource
 */
class CustomerCarResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'brand' => $this->brand,
            'color' => $this->color,
            'plate_letters' => $this->plate_letters,
            'plate_numbers' => $this->plate_numbers,
            'is_default' => (bool) $this->is_default,
        ];
    }
}
