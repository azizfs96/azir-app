<?php

namespace App\Engines\BeautyWellness;

use App\Engines\BusinessEngine;
use App\Models\Store;

/**
 * The MVP's only business engine (spec §2): salons, spas, beauty centres,
 * massage centres, nail and hair salons.
 *
 * Deliberately NOT a "salon template". It is a configurable appointment engine
 * that happens to ship with beauty defaults (spec §9: "Do NOT create a fixed
 * salon template. Create a configurable booking engine.").
 */
class BeautyWellnessEngine implements BusinessEngine
{
    public function key(): string
    {
        return 'beauty_wellness';
    }

    public function label(): array
    {
        return ['ar' => 'الجمال والعناية', 'en' => 'Beauty & Wellness'];
    }

    /**
     * The spec §10 toggles, with types and grouping.
     *
     * `group` decides where each appears: `onboarding` toggles are the small set
     * shown during setup (spec §11 — "Do not expose 50 technical settings"),
     * everything else lives under Settings.
     */
    public function configurationSchema(): array
    {
        return [
            'staff_selection' => ['type' => 'boolean', 'default' => false, 'group' => 'onboarding'],
            'branch_selection' => ['type' => 'boolean', 'default' => false, 'group' => 'onboarding'],
            'payment_required' => ['type' => 'boolean', 'default' => false, 'group' => 'onboarding'],
            'deposit_required' => ['type' => 'boolean', 'default' => false, 'group' => 'onboarding'],
            'allow_cancellation' => ['type' => 'boolean', 'default' => true, 'group' => 'onboarding'],
            'allow_rescheduling' => ['type' => 'boolean', 'default' => true, 'group' => 'onboarding'],

            'customer_notes' => ['type' => 'boolean', 'default' => true, 'group' => 'advanced'],
            'guest_booking' => ['type' => 'boolean', 'default' => false, 'group' => 'advanced'],
            'deposit_type' => ['type' => 'enum:percent,fixed', 'default' => 'percent', 'group' => 'advanced'],
            'deposit_value' => ['type' => 'decimal', 'default' => 25.00, 'group' => 'advanced'],
            'cancellation_deadline_hours' => ['type' => 'integer', 'default' => 4, 'group' => 'advanced'],
            'refund_policy' => ['type' => 'enum:full,deposit_forfeited,none', 'default' => 'deposit_forfeited', 'group' => 'advanced'],
            'reschedule_deadline_hours' => ['type' => 'integer', 'default' => 4, 'group' => 'advanced'],
            'auto_confirm' => ['type' => 'boolean', 'default' => true, 'group' => 'advanced'],
            'min_lead_time_minutes' => ['type' => 'integer', 'default' => 60, 'group' => 'advanced'],
            'max_advance_days' => ['type' => 'integer', 'default' => 60, 'group' => 'advanced'],
            'reminder_hours_before' => ['type' => 'integer', 'default' => 24, 'group' => 'advanced'],
        ];
    }

    public function defaultConfiguration(): array
    {
        return array_map(
            fn (array $field) => $field['default'],
            $this->configurationSchema(),
        );
    }

    /**
     * ====================================================================
     * The customer journey as data (spec §9, §41).
     *
     * Merchant A (staff selection on):
     *     service -> staff -> date -> time -> payment -> confirm
     * Merchant B (off, 3 branches):
     *     branch -> service -> date -> time -> confirm
     *
     * Same code. Different data. That is the whole point — Flutter renders one
     * widget per STEP TYPE, never one screen per merchant (§30).
     *
     * Steps that would ask the customer a question with only one possible
     * answer are omitted entirely (spec §16, §41: "Do not add unnecessary
     * screens").
     * ====================================================================
     */
    public function flow(Store $store): array
    {
        $settings = $store->bookingSettings;
        $steps = [];

        // Branch — only when the merchant enabled it AND there is a real choice.
        if ($store->requiresBranchSelection()) {
            $steps[] = ['step' => 'branch', 'required' => true];
        }

        $steps[] = ['step' => 'service', 'required' => true, 'multi' => false];

        // Staff — only if exposed. When off, StaffAssigner picks one server-side
        // and the customer never sees this question (spec §9 Merchant B).
        if ($settings?->staff_selection) {
            $steps[] = ['step' => 'staff', 'required' => true, 'allow_any' => true];
        }

        $steps[] = ['step' => 'date', 'required' => true];
        $steps[] = ['step' => 'time', 'required' => true];

        if ($settings?->customer_notes) {
            $steps[] = ['step' => 'notes', 'required' => false];
        }

        /*
         * Payment step.
         *
         * Online payment is switched off platform-wide for the MVP
         * (config/wasla.php payments.online_enabled). While it is off, EVERY
         * flow is pay-at-store regardless of what a store row says — a merchant
         * must never be able to enable a payment mode that has no provider
         * behind it.
         *
         * The branch below is the seam for turning it back on later.
         */
        if (config('wasla.payments.online_enabled') && $settings?->payment_required) {
            $steps[] = [
                'step' => 'payment',
                'required' => true,
                'mode' => $settings->deposit_required ? 'deposit' : 'full',
                'deposit_type' => $settings->deposit_type,
                'deposit_value' => (float) $settings->deposit_value,
            ];
        } else {
            // Still an explicit step: the customer should know they pay in store.
            $steps[] = ['step' => 'payment', 'required' => false, 'mode' => 'pay_at_store'];
        }

        $steps[] = ['step' => 'confirm', 'required' => true];

        return $steps;
    }

    /**
     * Services grouped by category, for the storefront (spec §8, §31).
     */
    public function catalog(Store $store): array
    {
        $categories = $store->serviceCategories()
            ->where('is_active', true)
            ->orderBy('sort_order')
            ->with(['services' => fn ($query) => $query->where('is_active', true)->orderBy('sort_order')])
            ->get();

        $uncategorised = $store->services()
            ->where('is_active', true)
            ->whereNull('service_category_id')
            ->orderBy('sort_order')
            ->get();

        return [
            'categories' => $categories,
            'uncategorised' => $uncategorised,
        ];
    }
}
