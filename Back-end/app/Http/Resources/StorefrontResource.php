<?php

namespace App\Http\Resources;

use App\Domain\Merchant\OpeningHoursSummary;
use App\Engines\BusinessEngineRegistry;
use App\Http\Resources\MenuCategoryResource;
use App\Http\Resources\MenuItemResource;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * ============================================================================
 * THE DYNAMIC MERCHANT EXPERIENCE (spec §31, §8, §43)
 *
 * This single payload is what makes "one app, many merchants" work. Flutter
 * renders a storefront entirely from this — it holds no merchant-specific code,
 * no per-merchant screens and no build-time configuration.
 *
 *   {
 *     "store":         { identity + branding }
 *     "configuration": { the §10 toggles }
 *     "flow":          [ ordered steps the customer walks ]   <- the key part
 *     "services":      [ ... ]
 *     "branches":      [ ... ]
 *     "staff":         [ ... ]                                <- omitted if hidden
 *   }
 *
 * `flow` comes from the store's BusinessEngine, so adding a Restaurant vertical
 * later changes what a client renders WITHOUT an app release (§44).
 * ============================================================================
 */
class StorefrontResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $locale = app()->getLocale();
        $engine = app(BusinessEngineRegistry::class)->for($this->resource);
        $settings = $this->bookingSettings;

        /*
         * Staff are serialized ONLY when the merchant exposes them.
         *
         * When staff_selection is off the customer must not receive the roster
         * at all — not merely have it hidden in the UI. The server assigns
         * someone at booking time instead (spec §9 Merchant B).
         */
        $exposeStaff = (bool) $settings?->staff_selection;

        return [
            'store' => [
                'id' => $this->public_token,
                'token' => $this->public_token,
                'name' => $this->displayName($locale),
                'name_ar' => $this->name_ar,
                'name_en' => $this->name_en,
                'description' => $locale === 'en'
                    ? ($this->description_en ?: $this->description_ar)
                    : $this->description_ar,
                'logo' => $this->logo_path,
                'cover' => $this->cover_path,
                'brand_color' => $this->brand_color,
                'type' => $this->business_type,
                // Open/closed right now, from the branches' opening hours.
                'is_open' => $this->isOpenNow(),
                'phone' => $this->phone,
                'instagram' => $this->instagram,
                'timezone' => $this->timezone,
                'currency' => $this->currency,
                'gender_policy' => $this->gender_policy,
                'deep_link' => $this->deepLink(),

                // A merchant an admin actually reviewed and approved (spec §39).
                // Not a vanity badge — it is the platform vouching for them.
                'is_verified' => $this->merchant?->isOperational() ?? false,
            ],

            /*
             * Opening hours and location, summarised for the storefront header.
             *
             * Taken from the default branch: a single-branch merchant is the
             * common case, and a header showing three sets of hours would be
             * noise rather than information.
             */
            'hours' => $this->hoursSummary(),
            'location' => $this->locationSummary(),

            // The §10 toggles the app renders itself from.
            /*
             * Each engine OWNS the shape of its configuration. Beauty emits the
             * §10 booking toggles; a restaurant emits its order toggles (pickup,
             * dine-in, delivery, curbside and their fees) read from the store's
             * settings, falling back to the engine defaults per key so the app
             * always receives a complete object.
             */
            'configuration' => $this->configurationPayload($engine, $settings),

            // The customer journey, as data.
            'flow' => $engine->flow($this->resource),

            'policies' => [
                'cancellation' => [
                    'allowed' => (bool) $settings?->allow_cancellation,
                    'deadline_hours' => $settings?->cancellation_deadline_hours,
                    'refund_policy' => $settings?->refund_policy,
                    // Shown to the customer BEFORE they confirm (spec §21).
                    'text' => $this->cancellationText($settings, $locale),
                ],
                'rescheduling' => [
                    'allowed' => (bool) $settings?->allow_rescheduling,
                    'deadline_hours' => $settings?->reschedule_deadline_hours,
                ],
                'booking_window' => [
                    'min_lead_time_minutes' => $settings?->min_lead_time_minutes,
                    'max_advance_days' => $settings?->max_advance_days,
                ],
            ],

            /*
             * The restaurant menu, only for restaurant stores. Beauty payloads
             * are byte-identical to before this key existed — engines add to
             * the storefront, they never reshape each other's.
             *
             * A spread rather than $this->when(): the controller serialises
             * this resource with a manual toArray() call, which skips
             * Laravel's MissingValue filtering — when() would leak the key
             * into every beauty payload as an empty object.
             */
            ...($engine->key() === 'restaurant'
                ? ['menu' => (function () use ($engine) {
                    $catalog = $engine->catalog($this->resource);

                    return [
                        'categories' => MenuCategoryResource::collection($catalog['categories']),
                        'uncategorised' => MenuItemResource::collection($catalog['uncategorised']),
                    ];
                })()]
                : []),

            'categories' => ServiceCategoryResource::collection($this->whenLoaded('serviceCategories')),
            'services' => ServiceResource::collection($this->whenLoaded('services')),

            // Only meaningful when there is a genuine choice (spec §16).
            'branches' => BranchResource::collection($this->whenLoaded('activeBranches')),
            'requires_branch_selection' => $this->requiresBranchSelection(),

            'staff' => $exposeStaff
                ? StaffResource::collection($this->whenLoaded('staff'))
                : [],
        ];
    }

    /**
     * The configuration object the app renders from.
     *
     * A restaurant's toggles live in the engine's own schema, so we read each
     * declared key from the store's settings (falling back to the schema
     * default). Beauty keeps its dedicated §10 shape via toConfiguration().
     *
     * @return array<string, mixed>
     */
    private function configurationPayload(mixed $engine, mixed $settings): array
    {
        if ($engine->key() !== 'restaurant') {
            return $settings?->toConfiguration() ?? $engine->defaultConfiguration();
        }

        $config = [];

        foreach ($engine->configurationSchema() as $key => $field) {
            $value = $settings?->getAttribute($key) ?? $field['default'];

            $config[$key] = match ($field['type'] ?? 'boolean') {
                'integer' => (int) $value,
                'decimal', 'number' => (float) $value,
                'string' => (string) ($value ?? ''),
                default => (bool) $value,
            };
        }

        return $config;
    }

    /**
     * @return array<string, mixed>|null
     */
    private function hoursSummary(): ?array
    {
        $branch = $this->defaultBranch();

        if ($branch === null) {
            return null;
        }

        $branch->loadMissing('schedules');

        return OpeningHoursSummary::for($branch, app()->getLocale());
    }

    /**
     * @return array<string, mixed>|null
     */
    private function locationSummary(): ?array
    {
        $branch = $this->defaultBranch();

        if ($branch === null) {
            return null;
        }

        return [
            'city' => $branch->city,
            'address' => $branch->address_line,
            'maps_url' => $branch->google_maps_url,
            'latitude' => $branch->latitude !== null ? (float) $branch->latitude : null,
            'longitude' => $branch->longitude !== null ? (float) $branch->longitude : null,
        ];
    }

    /**
     * The cancellation policy in plain language, so the app can show it verbatim
     * rather than reassembling a sentence from booleans (spec §21).
     */
    private function cancellationText(mixed $settings, string $locale): ?string
    {
        if ($settings === null || ! $settings->allow_cancellation) {
            return __('booking.cancellation_not_allowed');
        }

        return __('booking.cancellation_policy', ['hours' => $settings->cancellation_deadline_hours]);
    }
}
