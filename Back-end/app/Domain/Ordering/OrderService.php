<?php

namespace App\Domain\Ordering;

use App\Domain\Ordering\Events\OrderStatusChanged;
use App\Domain\Ordering\Exceptions\OrderNotPlaceable;
use App\Models\Branch;
use App\Models\CustomerAddress;
use App\Models\CustomerCar;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\Customer;
use App\Models\Store;
use Illuminate\Support\Facades\DB;

/**
 * ============================================================================
 * PLACING AN ORDER (RestaurantEngine, R3)
 *
 * The write-path authority for restaurants — the exact counterpart of
 * BookingService for bookings, and it carries the same hard-won lesson: the
 * CLIENT IS NEVER TRUSTED. Every price is recomputed here from the stored
 * menu, every option is verified to belong to its dish, and every group's
 * min/max selection rule is enforced server-side. The cart's own total is
 * ignored entirely.
 *
 * What the client sends is only a list of intents:
 *   [{ item_id, option_ids: [..], quantity }, ..]
 * and this decides what — if anything — that legally costs.
 * ============================================================================
 */
class OrderService
{
    /**
     * @param  array<int, array{item_id:int, option_ids?: array<int,int>, quantity:int}>  $lines
     *
     * @throws OrderNotPlaceable
     */
    public function place(
        Store $store,
        array $lines,
        string $fulfillmentType,
        ?Branch $branch = null,
        ?Customer $customer = null,
        ?string $notes = null,
        ?string $tableNumber = null,
        ?CustomerAddress $deliveryAddress = null,
        ?CustomerCar $car = null,
    ): Order {
        if ($lines === []) {
            throw new OrderNotPlaceable('EMPTY_CART', 'An order must contain at least one item.');
        }

        $settings = $store->bookingSettings;
        $engineKey = $store->business_type;

        if ($engineKey !== 'restaurant') {
            throw new OrderNotPlaceable('NOT_A_RESTAURANT', 'This store does not take orders.');
        }

        // Delivery needs a destination, and it must be the ordering customer's
        // own address — never another customer's id smuggled in.
        if ($fulfillmentType === 'delivery') {
            if (! ($settings?->order_delivery ?? false)) {
                throw new OrderNotPlaceable('FULFILLMENT_UNAVAILABLE', 'Delivery is not offered here.');
            }

            if ($deliveryAddress === null) {
                throw new OrderNotPlaceable('DELIVERY_ADDRESS_REQUIRED', 'A delivery order needs an address.');
            }

            if ($customer === null || $deliveryAddress->customer_id !== $customer->id) {
                throw new OrderNotPlaceable('ADDRESS_NOT_YOURS', 'That address is not on this account.');
            }
        }

        // Curbside needs the customer's own car to bring the food to.
        if ($fulfillmentType === 'curbside') {
            if (! ($settings?->order_curbside ?? false)) {
                throw new OrderNotPlaceable('FULFILLMENT_UNAVAILABLE', 'Curbside is not offered here.');
            }

            if ($car === null) {
                throw new OrderNotPlaceable('CAR_REQUIRED', 'A curbside order needs a car.');
            }

            if ($customer === null || $car->customer_id !== $customer->id) {
                throw new OrderNotPlaceable('CAR_NOT_YOURS', 'That car is not on this account.');
            }
        }

        $branch ??= $store->defaultBranch();

        return DB::transaction(function () use (
            $store, $lines, $fulfillmentType, $branch, $customer, $notes, $tableNumber,
            $settings, $deliveryAddress, $car,
        ): Order {
            $isDelivery = $fulfillmentType === 'delivery';

            $order = new Order([
                'branch_id' => $branch?->id,
                'customer_id' => $customer?->id,
                'fulfillment_type' => $fulfillmentType,
                'table_number' => $fulfillmentType === 'dine_in' ? $tableNumber : null,
                'customer_notes' => $notes,
                'source' => 'app',
            ]);

            $order->forceFill([
                'merchant_id' => $store->merchant_id,
                'store_id' => $store->id,
                'status' => OrderStatus::Placed,
            ]);

            // Snapshot the destination AS SENT, so a later address edit/delete
            // never rewrites where this order went.
            if ($isDelivery) {
                $order->forceFill([
                    'customer_address_id' => $deliveryAddress->id,
                    'delivery_address' => $deliveryAddress->address_text,
                    'delivery_details' => $deliveryAddress->details,
                    'delivery_latitude' => $deliveryAddress->latitude,
                    'delivery_longitude' => $deliveryAddress->longitude,
                ]);
            }

            // Snapshot the car for curbside, as sent.
            if ($fulfillmentType === 'curbside' && $car !== null) {
                $order->forceFill([
                    'customer_car_id' => $car->id,
                    'car_description' => $car->description(),
                ]);
            }

            $order->save();

            $subtotal = 0.0;

            foreach ($lines as $index => $line) {
                $subtotal += $this->addLine($order, $store, $line, $index);
            }

            // Delivery pricing is the server's: enforce the minimum, then add the
            // flat fee. The client's figures are never trusted.
            $deliveryFee = 0.0;

            if ($isDelivery) {
                $minOrder = (float) ($settings->delivery_min_order ?? 0);

                if ($minOrder > 0 && round($subtotal, 2) < $minOrder) {
                    throw new OrderNotPlaceable(
                        'BELOW_MIN_ORDER',
                        "Delivery needs a subtotal of at least {$minOrder}.",
                    );
                }

                $deliveryFee = round((float) ($settings->delivery_fee ?? 0), 2);
            }

            // VAT (spec §35). Added on top of the taxable base (subtotal +
            // delivery — delivery is a taxable supply). Off unless the store is
            // registered; the seller's details are snapshotted so a later
            // settings change never rewrites an issued invoice.
            $subtotalRounded = round($subtotal, 2);
            $taxRate = 0.0;
            $taxAmount = 0.0;
            $sellerName = null;
            $taxNumber = null;
            $nationalAddress = null;
            $commercialRegistration = null;

            if ((bool) ($settings->tax_enabled ?? false)) {
                $taxRate = round((float) ($settings->tax_rate ?? 0), 2);
                $taxAmount = round(($subtotalRounded + $deliveryFee) * $taxRate / 100, 2);
                $sellerName = $settings->legal_name ?: $store->displayName('ar');
                $taxNumber = $settings->tax_number ?: null;
                $nationalAddress = $settings->national_address ?: null;
                $commercialRegistration = $settings->commercial_registration ?: null;
            }

            $order->forceFill([
                'subtotal' => $subtotalRounded,
                'delivery_fee' => $deliveryFee,
                'tax_rate' => $taxRate,
                'tax_amount' => $taxAmount,
                'seller_name' => $sellerName,
                'tax_number' => $taxNumber,
                'national_address' => $nationalAddress,
                'commercial_registration' => $commercialRegistration,
                'total' => round($subtotalRounded + $deliveryFee + $taxAmount, 2),
            ])->save();

            /*
             * Auto-accept for merchants who never watch a dashboard: the order
             * jumps straight to accepted and commits the engine's default prep
             * time. Everyone else leaves it 'placed' for the kitchen to accept.
             */
            if ($settings?->auto_accept_orders ?? false) {
                $order->transitionTo(OrderStatus::Accepted, 'system', [
                    'prep_minutes' => $settings->default_prep_minutes,
                ]);
            } else {
                // Announce creation so notifications fire even without a
                // status change (the customer's "order received").
                OrderStatusChanged::dispatch($order, null, OrderStatus::Placed, 'customer');
            }

            return $order->load('items.options');
        });
    }

    /**
     * Validate and persist one line; returns its line total.
     *
     * @param  array{item_id:int, option_ids?: array<int,int>, quantity:int}  $line
     */
    private function addLine(Order $order, Store $store, array $line, int $index): float
    {
        $quantity = (int) ($line['quantity'] ?? 0);

        if ($quantity < 1) {
            throw new OrderNotPlaceable('BAD_QUANTITY', "Line {$index} has no quantity.");
        }

        /** @var MenuItem|null $item */
        $item = MenuItem::query()
            ->where('store_id', $store->id)
            ->where('is_active', true)
            ->with('optionGroups.options')
            ->find($line['item_id'] ?? 0);

        if ($item === null) {
            throw new OrderNotPlaceable('ITEM_NOT_FOUND', "Line {$index}: no such dish.");
        }

        if (! $item->is_available) {
            throw new OrderNotPlaceable('ITEM_UNAVAILABLE', "Line {$index}: '{$item->name_ar}' is sold out.");
        }

        $chosenIds = array_map('intval', $line['option_ids'] ?? []);
        $unitPrice = (float) $item->price;

        // Snapshots to write once the whole line validates: each entry already
        // carries its group name, captured here in the group loop (so we never
        // lazy-load $option->group later).
        $snapshots = [];
        $matchedIds = [];

        // Validate group by group: only options that BELONG to this dish, and
        // the group's own min/max selection rule.
        foreach ($item->optionGroups as $group) {
            $idsInGroup = $group->options->pluck('id')->all();
            $picked = array_values(array_intersect($chosenIds, $idsInGroup));
            $count = count($picked);

            if ($count < $group->min_select || $count > $group->max_select) {
                throw new OrderNotPlaceable(
                    'OPTION_RULE_VIOLATED',
                    "Line {$index}: group '{$group->name_ar}' needs "
                        ."{$group->min_select}-{$group->max_select} selections, got {$count}.",
                );
            }

            foreach ($picked as $optionId) {
                $option = $group->options->firstWhere('id', $optionId);

                if (! $option->is_available) {
                    throw new OrderNotPlaceable(
                        'OPTION_UNAVAILABLE',
                        "Line {$index}: option '{$option->name_ar}' is unavailable.",
                    );
                }

                $matchedIds[] = $optionId;
                $unitPrice += (float) $option->price_delta;
                $snapshots[] = [
                    'menu_option_id' => $option->id,
                    'group_name' => $group->name_ar,
                    'name' => $option->name_ar,
                    'price_delta' => round((float) $option->price_delta, 2),
                ];
            }
        }

        // Any option id the client sent that is NOT part of this dish is a
        // tampering attempt or a stale cart — refuse rather than silently drop.
        $strayIds = array_diff($chosenIds, $matchedIds);
        if ($strayIds !== []) {
            throw new OrderNotPlaceable(
                'OPTION_NOT_ON_ITEM',
                "Line {$index}: options [".implode(',', $strayIds)."] do not belong to this dish.",
            );
        }

        $lineTotal = round($unitPrice * $quantity, 2);

        $orderItem = $order->items()->create([
            'menu_item_id' => $item->id,
            'name' => $item->name_ar,
            'unit_price' => round($unitPrice, 2),
            'quantity' => $quantity,
            'line_total' => $lineTotal,
        ]);

        foreach ($snapshots as $snapshot) {
            $orderItem->options()->create($snapshot);
        }

        return $lineTotal;
    }
}
