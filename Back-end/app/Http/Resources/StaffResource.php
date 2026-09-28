<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A staff member, as shown to a CUSTOMER.
 *
 * Only ever serialized when the merchant enabled staff_selection — the store
 * payload omits the whole collection otherwise (spec §9).
 */
class StaffResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $locale = app()->getLocale();

        return [
            'id' => $this->id,
            'name' => $this->name,
            'title' => $locale === 'en' ? ($this->title_en ?: $this->title_ar) : $this->title_ar,
            'avatar' => $this->avatar_path,
        ];
    }
}
