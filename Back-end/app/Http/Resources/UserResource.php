<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The authenticated user, for both apps (ARCHITECTURE.md §7).
 *
 * Only ever exposes what the client needs. Note there is no merchant_id here:
 * the client has no business knowing it, and must never send it back (§4).
 */
class UserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'phone' => $this->phone,
            'email' => $this->email,
            'role' => $this->role,
            'locale' => $this->locale,
            'phone_verified' => $this->phone_verified_at !== null,

            'customer' => $this->whenLoaded('customer', fn () => [
                'id' => $this->customer->id,
                'first_name' => $this->customer->first_name,
                'last_name' => $this->customer->last_name,
                'gender' => $this->customer->gender,
            ]),

            'merchant' => $this->whenLoaded('merchant', fn () => [
                'display_name' => $this->merchant->display_name,
                'status' => $this->merchant->status,
                'onboarding_step' => $this->merchant->onboarding_step,
                'onboarding_complete' => $this->merchant->hasCompletedOnboarding(),
            ]),
        ];
    }
}
