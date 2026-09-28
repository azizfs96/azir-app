<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Engines\BusinessEngineRegistry;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Booking and store settings (spec §10, §21, §22).
 *
 * This is where the "50 technical settings" live — deliberately NOT in
 * onboarding (§11).
 */
class SettingsController extends MerchantController
{
    /**
     * GET /merchant/settings/booking
     */
    public function booking(): JsonResponse
    {
        $store = $this->merchantStore();
        $engine = app(BusinessEngineRegistry::class)->for($store);

        return response()->json([
            'settings' => $store->bookingSettings,
            // The dashboard renders its form from this, so a new engine toggle
            // appears without a React change (ARCHITECTURE.md §2.1).
            'schema' => $engine->configurationSchema(),
            'online_payment_available' => (bool) config('wasla.payments.online_enabled'),
        ]);
    }

    /**
     * PATCH /merchant/settings/booking
     */
    public function updateBooking(Request $request): JsonResponse
    {
        $store = $this->merchantStore();
        $engine = app(BusinessEngineRegistry::class)->for($store);

        /*
         * The engine OWNS its toggles: every key it declares in
         * configurationSchema() is validated from that declaration and saved.
         * That is what lets a merchant flip a new feature (delivery, curbside,
         * …) the moment the engine adds it — no change here or in React.
         */
        $rules = $this->rulesFromSchema($engine->configurationSchema());

        // Cross-vertical booking policy that is not part of an engine's own
        // schema still needs explicit rules.
        $rules += [
            'cancellation_deadline_hours' => ['sometimes', 'integer', 'min:0', 'max:168'],
            'refund_policy' => ['sometimes', 'in:full,deposit_forfeited,none'],
            'reschedule_deadline_hours' => ['sometimes', 'integer', 'min:0', 'max:168'],
            'auto_confirm' => ['sometimes', 'boolean'],
            'min_lead_time_minutes' => ['sometimes', 'integer', 'min:0', 'max:10080'],
            'max_advance_days' => ['sometimes', 'integer', 'min:1', 'max:365'],
            'reminder_hours_before' => ['sometimes', 'integer', 'min:1', 'max:168'],
            // Payment toggles are accepted but gated below.
            'payment_required' => ['sometimes', 'boolean'],
            'deposit_required' => ['sometimes', 'boolean'],
            'deposit_type' => ['sometimes', 'in:percent,fixed'],
            'deposit_value' => ['sometimes', 'numeric', 'min:0', 'max:99999.99'],
        ];

        $data = $request->validate($rules);

        /*
         * Online payment is switched off platform-wide for the MVP.
         *
         * Silently accepting payment_required = true would let a merchant
         * configure a checkout that does not exist, so it is refused with an
         * explanation instead.
         */
        if (! config('wasla.payments.online_enabled')) {
            $wantsPayment = ($data['payment_required'] ?? false) || ($data['deposit_required'] ?? false);

            if ($wantsPayment) {
                return response()->json([
                    'message' => __('merchant.online_payment_unavailable'),
                    'error_code' => 'ONLINE_PAYMENT_UNAVAILABLE',
                ], 422);
            }

            unset($data['payment_required'], $data['deposit_required']);
        }

        $store->bookingSettings->update($data);

        return response()->json(['settings' => $store->bookingSettings->fresh()]);
    }

    /**
     * Turn an engine's configurationSchema into validation rules, so a merchant
     * can save exactly the toggles their vertical declares — and nothing else.
     *
     * @param  array<string, array{type:string, default:mixed, group?:string}>  $schema
     * @return array<string, array<int, string>>
     */
    private function rulesFromSchema(array $schema): array
    {
        $rules = [];

        foreach ($schema as $key => $field) {
            $rules[$key] = match ($field['type'] ?? 'boolean') {
                'integer' => ['sometimes', 'integer', 'min:0', 'max:100000'],
                'decimal', 'number' => ['sometimes', 'numeric', 'min:0', 'max:99999.99'],
                'string' => ['sometimes', 'nullable', 'string', 'max:255'],
                default => ['sometimes', 'boolean'],
            };
        }

        return $rules;
    }

    /**
     * PATCH /merchant/settings/store — branding and identity.
     */
    /**
     * GET /merchant/settings/store — identity, branding and current media.
     */
    public function store(): JsonResponse
    {
        $store = $this->merchantStore();

        return response()->json([
            'store' => [
                // The vertical this store runs on — the dashboard shows "Menu"
                // for a restaurant and "Services" for beauty from this alone.
                'business_type' => $store->business_type,
                'name_ar' => $store->name_ar,
                'name_en' => $store->name_en,
                'description_ar' => $store->description_ar,
                'description_en' => $store->description_en,
                'brand_color' => $store->brand_color,
                'phone' => $store->phone,
                'instagram' => $store->instagram,
                'gender_policy' => $store->gender_policy,
                'is_published' => (bool) $store->is_published,
                // Absolute URLs: the dashboard shows a preview, and the paths
                // alone are meaningless to a browser.
                'logo_url' => $store->logo_path
                    ? \Illuminate\Support\Facades\Storage::disk('public')->url($store->logo_path)
                    : null,
                'cover_url' => $store->cover_path
                    ? \Illuminate\Support\Facades\Storage::disk('public')->url($store->cover_path)
                    : null,
            ],
        ]);
    }

    public function updateStore(Request $request): JsonResponse
    {
        $store = $this->merchantStore();

        $data = $request->validate([
            'name_ar' => ['sometimes', 'string', 'max:120'],
            'name_en' => ['sometimes', 'nullable', 'string', 'max:120'],
            'description_ar' => ['sometimes', 'nullable', 'string', 'max:1000'],
            'description_en' => ['sometimes', 'nullable', 'string', 'max:1000'],
            'brand_color' => ['sometimes', 'regex:/^#[0-9A-Fa-f]{6}$/'],
            'phone' => ['sometimes', 'nullable', 'string', 'max:20'],
            'instagram' => ['sometimes', 'nullable', 'string', 'max:80'],
            'gender_policy' => ['sometimes', 'in:all,women_only,men_only'],
            'timezone' => ['sometimes', 'timezone'],
        ]);

        $store->update($data);

        return response()->json(['store' => $store->fresh()]);
    }
}
