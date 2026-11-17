<?php

namespace App\Engines\Supermarket;

use App\Domain\Ordering\OrderStatus;
use App\Engines\BusinessEngine;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Store;

/**
 * ============================================================================
 * THE SUPERMARKET ENGINE — the third vertical: grocery delivery.
 *
 * Same catalogue tables as the restaurant (categories → products), but a
 * different business: products carry a unit ("1 كجم"), a compare-at price for
 * discounts and a stock count; there are no option groups to speak of, no
 * pickup or dine-in — every order is DELIVERED and PAID ON DELIVERY — and the
 * order moves placed → preparing → out_for_delivery → completed (delivered),
 * with no "accept" or "ready" step in between.
 * ============================================================================
 */
class SupermarketEngine implements BusinessEngine
{
    public function key(): string
    {
        return 'supermarket';
    }

    public function label(): array
    {
        return ['ar' => 'سوبرماركت', 'en' => 'Supermarket'];
    }

    public function takesOrders(): bool
    {
        return true;
    }

    /** Groceries only go to the door. */
    public function fulfillmentTypes(): array
    {
        return ['delivery'];
    }

    public function paymentMethod(): string
    {
        return 'cash_on_delivery';
    }

    /**
     * placed → preparing → out_for_delivery → completed. "Preparing" is the
     * store's acceptance; the driver (or the store) takes it out; hand-over
     * completes it. Rejection is only possible before preparation starts.
     */
    public function orderTransitions(): array
    {
        return [
            OrderStatus::Placed->value => [OrderStatus::Preparing, OrderStatus::Rejected, OrderStatus::Cancelled],
            OrderStatus::Preparing->value => [OrderStatus::OutForDelivery, OrderStatus::Cancelled],
            OrderStatus::OutForDelivery->value => [OrderStatus::Completed, OrderStatus::Cancelled],
            OrderStatus::Accepted->value => [OrderStatus::Preparing, OrderStatus::Cancelled],
            OrderStatus::Ready->value => [OrderStatus::OutForDelivery, OrderStatus::Cancelled],
            OrderStatus::Completed->value => [],
            OrderStatus::Rejected->value => [],
            OrderStatus::Cancelled->value => [],
        ];
    }

    /**
     * The merchant settings surface: delivery pricing (shared with the
     * restaurant), a minimum basket, auto-accept, and optional VAT. Pickup,
     * dine-in and curbside are not offered at all.
     */
    public function configurationSchema(): array
    {
        return [
            // Fulfilment is delivery-only; the flag stays declared (and true)
            // so every client that reads order_* keys sees a consistent shape.
            'order_pickup' => ['type' => 'boolean', 'default' => false, 'group' => 'orders'],
            'order_dine_in' => ['type' => 'boolean', 'default' => false, 'group' => 'orders'],
            'order_delivery' => ['type' => 'boolean', 'default' => true, 'group' => 'orders'],
            'order_curbside' => ['type' => 'boolean', 'default' => false, 'group' => 'orders'],
            'delivery_fee' => ['type' => 'decimal', 'default' => 0, 'group' => 'orders'],
            'delivery_min_order' => ['type' => 'decimal', 'default' => 0, 'group' => 'orders'],
            'delivery_pricing_mode' => ['type' => 'string', 'default' => 'fixed', 'group' => 'orders'],
            'delivery_base_fee' => ['type' => 'decimal', 'default' => 0, 'group' => 'orders'],
            'delivery_fee_per_km' => ['type' => 'decimal', 'default' => 0, 'group' => 'orders'],
            'delivery_tiers' => ['type' => 'array', 'default' => [], 'group' => 'orders'],
            'delivery_max_distance_km' => ['type' => 'decimal', 'default' => 0, 'group' => 'orders'],
            'delivery_road_factor' => ['type' => 'decimal', 'default' => 1.3, 'group' => 'orders'],
            // Auto-accept means "start preparing the moment it lands".
            'auto_accept_orders' => ['type' => 'boolean', 'default' => false, 'group' => 'orders'],
            'default_prep_minutes' => ['type' => 'integer', 'default' => 30, 'group' => 'orders'],
            'customer_notes' => ['type' => 'boolean', 'default' => true, 'group' => 'orders'],

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
        return array_map(fn (array $field) => $field['default'], $this->configurationSchema());
    }

    public function flow(Store $store): array
    {
        return [
            ['step' => 'menu', 'required' => true],
            ['step' => 'cart', 'required' => true],
            ['step' => 'payment', 'required' => false, 'mode' => 'cash_on_delivery'],
            ['step' => 'confirm', 'required' => true],
        ];
    }

    /**
     * Categories → products. Same shape as the restaurant catalogue so the
     * resources, the cart and the order pipeline are shared; the product-only
     * fields (unit, compare-at price, stock) ride along on the item.
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

        return ['categories' => $categories, 'uncategorised' => $uncategorised];
    }
}
