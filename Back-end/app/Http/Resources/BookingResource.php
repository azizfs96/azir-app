<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A booking as the CUSTOMER sees it (spec §18).
 *
 * Times are rendered in the store's timezone with an explicit offset, so the
 * client never guesses (ARCHITECTURE.md §5.4).
 */
class BookingResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $locale = app()->getLocale();
        $timezone = $this->store?->timezone ?? config('wasla.default_timezone');

        return [
            'id' => $this->id,
            'reference' => $this->reference,

            'status' => $this->booking_status->value,
            'payment_status' => $this->payment_status,

            'starts_at' => $this->starts_at->setTimezone($timezone)->toIso8601String(),
            'ends_at' => $this->ends_at->setTimezone($timezone)->toIso8601String(),
            'timezone' => $timezone,
            'duration_minutes' => $this->duration_minutes,

            'price' => (float) $this->price,
            'currency' => $this->currency,
            // Recorded but never charged while online payment is off (§20).
            'deposit_amount' => (float) $this->deposit_amount,
            'paid_amount' => (float) $this->paid_amount,

            'store' => $this->whenLoaded('store', fn () => [
                'token' => $this->store->public_token,
                'name' => $this->store->displayName($locale),
                'logo' => $this->store->logo_path,
                'phone' => $this->store->phone,
            ]),

            'service' => $this->whenLoaded('service', fn () => [
                'id' => $this->service->id,
                'name' => $this->service->displayName($locale),
            ]),

            'branch' => $this->whenLoaded('branch', fn () => $this->branch === null ? null : [
                'id' => $this->branch->id,
                'name' => $this->branch->displayName($locale),
                'address' => $this->branch->address_line,
                'google_maps_url' => $this->branch->google_maps_url,
            ]),

            /*
             * Staff identity is withheld unless the merchant exposes it (§9).
             *
             * Checking only `relationLoaded` is not enough: when staff_selection
             * is off the backend still ASSIGNS someone, and returning them here
             * would leak the roster the merchant deliberately chose to hide —
             * through the booking confirmation rather than the storefront.
             */
            'staff' => $this->when(
                (bool) $this->store?->bookingSettings?->staff_selection && $this->staff !== null,
                fn () => [
                    'id' => $this->staff->id,
                    'name' => $this->staff->name,
                ],
                null,
            ),

            'customer_notes' => $this->customer_notes,

            // Computed server-side so the app never re-implements policy logic.
            'can_cancel' => $this->isCancellableByCustomer(),
            'can_reschedule' => $this->isReschedulableByCustomer(),

            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}
