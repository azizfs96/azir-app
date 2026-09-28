<?php

namespace App\Engines\Restaurant;

use App\Engines\BusinessEngine;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Store;

/**
 * ============================================================================
 * THE RESTAURANT ENGINE — the second vertical (spec §43, §44)
 *
 * This class existing is the architecture's promise being kept: a restaurant
 * differs from a salon in its CATALOG (menu vs services), its JOURNEY (browse →
 * cart → order vs pick → schedule → book) and its FULFILMENT (an order the
 * kitchen accepts vs an appointment on a calendar). All three are declared
 * here as data; no core table changed and no beauty code was touched.
 *
 * What a restaurant does NOT have: staff selection, schedules, availability,
 * or slots. The booking domain never runs for these stores. Fulfilment is the
 * Orders domain (R1) — the restaurant analogue of BookingService.
 *
 * NOT a marketplace (§46), same as ever: each restaurant lives behind its own
 * QR. There is no cross-restaurant search, feed, or delivery network — the
 * comparison to Jahez is the MENU EXPERIENCE, not the aggregator.
 * ============================================================================
 */
class RestaurantEngine implements BusinessEngine
{
    public function key(): string
    {
        return 'restaurant';
    }

    public function label(): array
    {
        return ['ar' => 'مطعم', 'en' => 'Restaurant'];
    }

    /**
     * Drives the merchant Settings UI (R2), same contract as beauty.
     */
    public function configurationSchema(): array
    {
        return [
            // Which ways a customer can take their order. Each is a per-store
            // toggle the merchant flips from the dashboard; the app shows only
            // the enabled ones, and OrderService refuses a disabled one.
            'order_pickup' => ['type' => 'boolean', 'default' => true, 'group' => 'orders'],
            'order_dine_in' => ['type' => 'boolean', 'default' => true, 'group' => 'orders'],
            'order_delivery' => ['type' => 'boolean', 'default' => false, 'group' => 'orders'],
            'order_curbside' => ['type' => 'boolean', 'default' => false, 'group' => 'orders'],

            // Server-owned delivery pricing (only meaningful when order_delivery
            // is on): a flat fee added to the total, and an optional minimum
            // subtotal below which delivery is refused.
            'delivery_fee' => ['type' => 'decimal', 'default' => 0, 'group' => 'orders'],
            'delivery_min_order' => ['type' => 'decimal', 'default' => 0, 'group' => 'orders'],

            // Jahez-style: the restaurant ACCEPTS each order and commits to a
            // prep time. Auto-accept is for the food-truck who never looks at
            // a dashboard.
            'auto_accept_orders' => ['type' => 'boolean', 'default' => false, 'group' => 'orders'],
            'default_prep_minutes' => ['type' => 'integer', 'default' => 20, 'group' => 'orders'],

            'customer_notes' => ['type' => 'boolean', 'default' => true, 'group' => 'orders'],

            // VAT / ZATCA e-invoicing (spec §35). Optional per store: off by
            // default so a non-registered merchant is untouched. When on, the
            // order is taxed and the invoice carries the QR + VAT details.
            'tax_enabled' => ['type' => 'boolean', 'default' => false, 'group' => 'invoicing'],
            'tax_rate' => ['type' => 'decimal', 'default' => 15, 'group' => 'invoicing'],
            'tax_number' => ['type' => 'string', 'default' => '', 'group' => 'invoicing'],
            'commercial_registration' => ['type' => 'string', 'default' => '', 'group' => 'invoicing'],
            'legal_name' => ['type' => 'string', 'default' => '', 'group' => 'invoicing'],
            'national_address' => ['type' => 'string', 'default' => '', 'group' => 'invoicing'],
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
     * The journey as data. The app renders a menu-cart journey for these step
     * types; an older binary that predates them skips unknown steps rather
     * than crashing (the same forward-compatibility rule the booking flow has
     * always had).
     */
    public function flow(Store $store): array
    {
        return [
            ['step' => 'menu', 'required' => true],
            ['step' => 'cart', 'required' => true],
            // Pay on pickup/at the table — mirrors beauty's pay_at_store step
            // while online payment stays platform-disabled.
            ['step' => 'payment', 'required' => false, 'mode' => 'pay_at_store'],
            ['step' => 'confirm', 'required' => true],
        ];
    }

    /**
     * The full menu tree: categories → items → option groups → options.
     *
     * Only active/available layers are exposed to customers; the merchant
     * dashboard reads the unfiltered tree through its own endpoints instead.
     */
    public function catalog(Store $store): array
    {
        $itemScope = fn ($query) => $query
            ->where('is_active', true)
            ->orderBy('sort_order')
            ->orderBy('id')
            ->with(['optionGroups.options' => fn ($q) => $q->where('is_available', true)]);

        $categories = MenuCategory::query()
            ->where('store_id', $store->id)
            ->where('is_active', true)
            ->orderBy('sort_order')
            ->orderBy('id')
            ->with(['items' => $itemScope])
            ->get();

        $uncategorised = MenuItem::query()
            ->where('store_id', $store->id)
            ->whereNull('menu_category_id')
            ->tap($itemScope)
            ->get();

        return [
            'categories' => $categories,
            'uncategorised' => $uncategorised,
        ];
    }
}
