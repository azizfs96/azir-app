<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Domain\Discovery\StoreResolver;
use App\Domain\Ordering\Exceptions\OrderNotPlaceable;
use App\Domain\Ordering\OrderService;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Branch;
use App\Models\CustomerStore;
use App\Models\Order;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * Customer restaurant orders (RestaurantEngine, R3).
 *
 * Mirrors the customer BookingController: every id is resolved THROUGH the
 * store token, the order is priced server-side, and the customer only ever
 * sees their own orders.
 */
class OrderController extends Controller
{
    public function __construct(
        private readonly OrderService $orders,
        private readonly StoreResolver $resolver,
    ) {}

    /**
     * POST /orders
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'store_token' => ['required', 'string', 'max:20'],
            'fulfillment_type' => ['required', 'in:pickup,dine_in,delivery,curbside'],
            'table_number' => ['sometimes', 'nullable', 'string', 'max:20'],
            // The chosen pickup branch; must belong to this store (checked below).
            'branch_id' => ['sometimes', 'nullable', 'integer'],
            // The customer's own saved address (central), required for delivery.
            'address_id' => ['required_if:fulfillment_type,delivery', 'integer'],
            // The customer's own saved car (central), required for curbside.
            'car_id' => ['required_if:fulfillment_type,curbside', 'integer'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:500'],
            'items' => ['required', 'array', 'min:1', 'max:50'],
            'items.*.item_id' => ['required', 'integer'],
            'items.*.quantity' => ['required', 'integer', 'min:1', 'max:50'],
            'items.*.option_ids' => ['sometimes', 'array', 'max:30'],
            'items.*.option_ids.*' => ['integer'],
        ]);

        $store = $this->resolver->resolve($data['store_token']);

        if ($store === null) {
            return response()->json([
                'message' => __('errors.store_unavailable'),
                'error_code' => 'STORE_NOT_FOUND',
            ], 404);
        }

        // Honour the merchant's fulfilment configuration server-side.
        $settings = $store->bookingSettings;
        $type = $data['fulfillment_type'];
        $allowed = match ($type) {
            'dine_in' => (bool) ($settings->order_dine_in ?? true),
            'delivery' => (bool) ($settings->order_delivery ?? false),
            'curbside' => (bool) ($settings->order_curbside ?? false),
            default => (bool) ($settings->order_pickup ?? true),
        };

        if (! $allowed) {
            return response()->json([
                'message' => __('errors.fulfillment_unavailable'),
                'error_code' => 'FULFILLMENT_UNAVAILABLE',
            ], 422);
        }

        // The customer's chosen pickup branch, but only if it really belongs to
        // this store — otherwise fall back to the default. The server owns this.
        $branch = $store->defaultBranch();
        if (! empty($data['branch_id'])) {
            $chosen = $store->activeBranches()->whereKey($data['branch_id'])->first();
            if ($chosen !== null) {
                $branch = $chosen;
            }
        }
        $customer = $request->user()->customer;

        // Pull the chosen address from the customer's OWN central list — a store
        // never supplies it, and an id that isn't theirs resolves to null and is
        // refused by OrderService.
        $deliveryAddress = null;

        if ($type === 'delivery') {
            $deliveryAddress = $customer?->addresses()->find($data['address_id']);

            if ($deliveryAddress === null) {
                return response()->json([
                    'message' => __('errors.not_found'),
                    'error_code' => 'ADDRESS_NOT_FOUND',
                ], 422);
            }
        }

        // Pull the chosen car from the customer's OWN central list for curbside.
        $car = null;

        if ($type === 'curbside') {
            $car = $customer?->cars()->find($data['car_id']);

            if ($car === null) {
                return response()->json([
                    'message' => __('errors.not_found'),
                    'error_code' => 'CAR_NOT_FOUND',
                ], 422);
            }
        }

        try {
            $order = $this->orders->place(
                store: $store,
                lines: $data['items'],
                fulfillmentType: $type,
                branch: $branch,
                customer: $customer,
                notes: $data['notes'] ?? null,
                tableNumber: $data['table_number'] ?? null,
                deliveryAddress: $deliveryAddress,
                car: $car,
            );
        } catch (OrderNotPlaceable $e) {
            return response()->json([
                'message' => __('errors.order_not_placeable'),
                'error_code' => $e->errorCode,
            ], 422);
        }

        if ($customer !== null) {
            $this->resolver->addToMyStores($store, $customer, 'order');

            CustomerStore::where('customer_id', $customer->id)
                ->where('store_id', $store->id)
                ->update(['last_booking_at' => CarbonImmutable::now()]);
        }

        return response()->json(
            new OrderResource($order->load(['store', 'customer', 'items.options', 'items.menuItem'])),
            201,
        );
    }

    /**
     * GET /orders?filter=active|past
     */
    public function index(Request $request): AnonymousResourceCollection
    {
        $customer = $request->user()->customer;
        $filter = $request->query('filter', 'active');

        $query = Order::query()
            ->withoutTenancy()
            ->where('customer_id', $customer?->id)
            ->with(['store', 'customer', 'items.options', 'items.menuItem'])
            ->latest();

        $query = $filter === 'past'
            ? $query->whereIn('status', ['completed', 'rejected', 'cancelled'])
            : $query->active();

        return OrderResource::collection($query->paginate(20));
    }

    /**
     * GET /orders/{id}
     *
     * Returned UNWRAPPED (no `data` envelope), byte-for-byte the shape POST
     * /orders and /cancel return — the app parses all three with one decoder,
     * so a `data` wrapper here (Laravel's default when a Resource is returned
     * directly) broke the tracking screen. response()->json() serialises the
     * resource without the envelope.
     */
    public function show(int $id, Request $request): JsonResponse
    {
        $order = Order::query()
            ->withoutTenancy()
            ->where('customer_id', $request->user()->customer?->id)
            ->with(['store', 'customer', 'items.options', 'items.menuItem'])
            ->find($id);

        return $order === null
            ? response()->json(['message' => __('errors.not_found'), 'error_code' => 'NOT_FOUND'], 404)
            : response()->json(new OrderResource($order));
    }

    /**
     * POST /orders/{id}/cancel — only before the kitchen accepts.
     */
    public function cancel(int $id, Request $request): JsonResponse
    {
        $order = Order::query()
            ->withoutTenancy()
            ->where('customer_id', $request->user()->customer?->id)
            ->find($id);

        if ($order === null) {
            return response()->json(['message' => __('errors.not_found'), 'error_code' => 'NOT_FOUND'], 404);
        }

        if (! $order->status->isCustomerCancellable()) {
            return response()->json([
                'message' => __('errors.order_not_cancellable'),
                'error_code' => 'ORDER_NOT_CANCELLABLE',
            ], 422);
        }

        $order->transitionTo(\App\Domain\Ordering\OrderStatus::Cancelled, 'customer', [
            'cancelled_by' => 'customer',
        ]);

        return response()->json(new OrderResource($order->load(['store', 'customer', 'items.options', 'items.menuItem'])));
    }
}
