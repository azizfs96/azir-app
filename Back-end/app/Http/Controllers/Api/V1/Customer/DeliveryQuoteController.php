<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Domain\Discovery\StoreResolver;
use App\Domain\Ordering\DeliveryPricing;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * "How much is delivery to my address from this branch?" — asked by the cart
 * as soon as an address/branch is chosen, so the customer sees the real fee
 * (and an out-of-range refusal) BEFORE placing the order. Order placement
 * runs the exact same pricing, so the two can never disagree.
 */
class DeliveryQuoteController extends Controller
{
    public function __construct(
        private readonly StoreResolver $resolver,
        private readonly DeliveryPricing $pricing,
    ) {}

    /** GET /me/delivery-quote?store_token=&address_id=&branch_id= */
    public function show(Request $request): JsonResponse
    {
        $data = $request->validate([
            'store_token' => ['required', 'string', 'max:20'],
            'address_id' => ['required', 'integer'],
            'branch_id' => ['sometimes', 'nullable', 'integer'],
        ]);

        $store = $this->resolver->resolve($data['store_token']);
        if ($store === null) {
            return response()->json(['message' => __('errors.store_unavailable'), 'error_code' => 'STORE_NOT_FOUND'], 404);
        }

        $address = $request->user()->customer?->addresses()->find($data['address_id']);
        if ($address === null) {
            return response()->json(['message' => __('errors.not_found'), 'error_code' => 'ADDRESS_NOT_FOUND'], 422);
        }

        $branch = $store->defaultBranch();
        if (! empty($data['branch_id'])) {
            $branch = $store->activeBranches()->whereKey($data['branch_id'])->first() ?? $branch;
        }

        $settings = $store->bookingSettings;
        $quote = $this->pricing->quote(
            $settings,
            $branch,
            $address->latitude !== null ? (float) $address->latitude : null,
            $address->longitude !== null ? (float) $address->longitude : null,
        );

        return response()->json([
            ...$quote->toArray(),
            'delivery_enabled' => (bool) ($settings?->order_delivery ?? false),
            'min_order' => (float) ($settings?->delivery_min_order ?? 0),
            'branch_id' => $branch?->id,
        ]);
    }
}
