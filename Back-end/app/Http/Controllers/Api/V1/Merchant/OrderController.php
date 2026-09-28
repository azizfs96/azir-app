<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Domain\Ordering\Exceptions\InvalidOrderTransition;
use App\Domain\Ordering\OrderStatus;
use App\Http\Resources\OrderResource;
use App\Models\Order;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

/**
 * Merchant-side order management (RestaurantEngine, R3).
 *
 * The kitchen's queue and the controls to move an order through its lifecycle.
 * merchant_id never appears here — BelongsToTenant scopes every read and the
 * policy guards every write (§4).
 */
class OrderController extends MerchantController
{
    /**
     * GET /merchant/orders?filter=active|past
     */
    public function index(Request $request): AnonymousResourceCollection
    {
        $filter = $request->query('filter', 'active');

        $query = Order::query()
            ->where('store_id', $this->merchantStore()->id)
            ->with(['customer', 'items.options'])
            ->latest();

        $query = $filter === 'past'
            ? $query->whereIn('status', ['completed', 'rejected', 'cancelled'])
            : $query->active();

        return OrderResource::collection($query->paginate(30));
    }

    /**
     * POST /merchant/orders/{id}/status
     *
     * Accept commits a prep time; reject records a reason. The state machine
     * refuses any illegal move with a 422.
     */
    public function updateStatus(int $id, Request $request): JsonResponse
    {
        $data = $request->validate([
            'status' => ['required', Rule::in([
                'accepted', 'preparing', 'ready', 'completed', 'rejected', 'cancelled',
            ])],
            'prep_minutes' => ['sometimes', 'integer', 'min:1', 'max:600'],
            'reason' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);

        $order = Order::with('items.options')->findOrFail($id);
        $this->authorize('update', $order);

        $target = OrderStatus::from($data['status']);

        $extra = [];
        if ($target === OrderStatus::Accepted) {
            // Prep time is committed on accept — use the sent value or fall
            // back to the store's configured default.
            $extra['prep_minutes'] = $data['prep_minutes']
                ?? $this->merchantStore()->bookingSettings?->default_prep_minutes
                ?? 20;
        }
        if ($target === OrderStatus::Rejected) {
            $extra['rejection_reason'] = $data['reason'] ?? null;
            $extra['cancelled_by'] = 'merchant';
        }
        if ($target === OrderStatus::Cancelled) {
            $extra['cancelled_by'] = 'merchant';
        }

        try {
            $order->transitionTo($target, 'merchant', $extra);
        } catch (InvalidOrderTransition $e) {
            return response()->json([
                'message' => $e->getMessage(),
                'error_code' => 'INVALID_ORDER_TRANSITION',
            ], 422);
        }

        return response()->json([
            'order' => new OrderResource($order->load(['customer', 'items.options'])),
            'allowed_transitions' => array_map(
                fn (OrderStatus $status) => $status->value,
                $order->status->allowedTransitions(),
            ),
        ]);
    }
}
