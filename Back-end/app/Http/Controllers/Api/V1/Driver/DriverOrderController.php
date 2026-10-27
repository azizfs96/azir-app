<?php

namespace App\Http\Controllers\Api\V1\Driver;

use App\Domain\Notification\NotificationDispatcher;
use App\Domain\Ordering\Exceptions\InvalidOrderTransition;
use App\Domain\Ordering\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\DriverResource;
use App\Http\Resources\OrderResource;
use App\Models\Driver;
use App\Models\Order;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * The driver app's view of the world: the store's delivery orders.
 *
 * Drivers are NOT tenant users (no TenantContext, no merchant policies) — every
 * query here is scoped explicitly to the driver's own store, and writes are
 * limited to "claim an unassigned order" and "advance MY order".
 */
class DriverOrderController extends Controller
{
    private const CLAIMABLE = ['accepted', 'preparing', 'ready'];

    private const MINE_ACTIVE = ['accepted', 'preparing', 'ready', 'out_for_delivery'];

    public function __construct(private readonly NotificationDispatcher $dispatcher) {}

    /** GET /driver/me */
    public function me(Request $request): JsonResponse
    {
        $driver = $this->driver($request);

        return response()->json([
            'driver' => new DriverResource($driver),
            'store' => [
                'token' => $driver->store?->public_token,
                'name' => $driver->store?->name_ar,
                'logo' => $driver->store?->logo_path,
            ],
        ]);
    }

    /** GET /driver/orders?filter=available|mine|past */
    public function index(Request $request): AnonymousResourceCollection
    {
        $driver = $this->driver($request);
        $filter = $request->query('filter', 'mine');

        $query = $this->base($driver)->with(['customer.user', 'items', 'branch', 'driver']);

        $query = match ($filter) {
            'available' => $query->whereNull('driver_id')->whereIn('status', self::CLAIMABLE)->oldest('accepted_at'),
            'past' => $query->where('driver_id', $driver->id)->whereIn('status', ['completed', 'cancelled'])->latest('completed_at'),
            default => $query->where('driver_id', $driver->id)->whereIn('status', self::MINE_ACTIVE)->oldest('assigned_at'),
        };

        return OrderResource::collection($query->paginate(30));
    }

    /** GET /driver/orders/{id} — unassigned, or mine. */
    public function show(int $id, Request $request): JsonResponse
    {
        $driver = $this->driver($request);
        $order = $this->base($driver)
            ->where(fn ($q) => $q->whereNull('driver_id')->orWhere('driver_id', $driver->id))
            ->with(['customer.user', 'items.options', 'branch', 'driver'])
            ->find($id);

        return $order === null
            ? $this->notFound()
            : response()->json(new OrderResource($order));
    }

    /**
     * POST /driver/orders/{id}/claim — take an unassigned delivery. Locked so
     * two drivers tapping at once cannot both win.
     */
    public function claim(int $id, Request $request): JsonResponse
    {
        $driver = $this->driver($request);

        $result = DB::transaction(function () use ($driver, $id) {
            $order = $this->base($driver)->whereKey($id)->lockForUpdate()->first();
            if ($order === null) {
                return 'not_found';
            }
            if ($order->driver_id !== null && $order->driver_id !== $driver->id) {
                return 'taken';
            }
            if (! in_array($order->status->value, self::CLAIMABLE, true)) {
                return 'not_claimable';
            }
            if ($order->driver_id === null) {
                $order->forceFill(['driver_id' => $driver->id, 'assigned_at' => CarbonImmutable::now()])->save();
            }

            return $order;
        });

        return match ($result) {
            'not_found' => $this->notFound(),
            'taken' => response()->json(['message' => __('errors.order_already_taken'), 'error_code' => 'ORDER_ALREADY_TAKEN'], 409),
            'not_claimable' => response()->json(['message' => __('errors.order_not_claimable'), 'error_code' => 'ORDER_NOT_CLAIMABLE'], 422),
            default => response()->json(new OrderResource($result->load(['customer.user', 'items.options', 'branch', 'driver']))),
        };
    }

    /**
     * POST /driver/orders/{id}/status — out_for_delivery (picked up) or
     * completed (handed over). Only for the driver's own order.
     */
    public function updateStatus(int $id, Request $request): JsonResponse
    {
        $driver = $this->driver($request);
        $data = $request->validate([
            'status' => ['required', Rule::in(['out_for_delivery', 'completed'])],
        ]);

        $order = $this->base($driver)->where('driver_id', $driver->id)->with('items.options')->find($id);
        if ($order === null) {
            return $this->notFound();
        }

        try {
            $order->transitionTo(OrderStatus::from($data['status']), 'driver');
        } catch (InvalidOrderTransition $e) {
            return response()->json(['message' => $e->getMessage(), 'error_code' => 'INVALID_ORDER_TRANSITION'], 422);
        }

        return response()->json(new OrderResource($order->load(['customer.user', 'items.options', 'branch', 'driver'])));
    }

    /**
     * POST /driver/location — the driver app's heartbeat while delivering.
     * One UPDATE on the driver row; nothing accumulates.
     */
    public function location(Request $request): JsonResponse
    {
        $driver = $this->driver($request);
        $data = $request->validate([
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
            'heading' => ['sometimes', 'nullable', 'integer', 'between:0,359'],
            'speed_kmh' => ['sometimes', 'nullable', 'numeric', 'between:0,300'],
        ]);

        $driver->forceFill([
            'last_latitude' => $data['latitude'],
            'last_longitude' => $data['longitude'],
            'last_heading' => $data['heading'] ?? null,
            'last_speed_kmh' => $data['speed_kmh'] ?? null,
            'last_located_at' => CarbonImmutable::now(),
        ])->save();

        return response()->json(['ok' => true, 'located_at' => $driver->last_located_at->toIso8601String()]);
    }

    // ---------------------------------------------------------------------

    private function driver(Request $request): Driver
    {
        $driver = Driver::withoutTenancy()->with('store')->where('user_id', $request->user()->id)->first();
        abort_if($driver === null, 403, __('errors.forbidden'));
        abort_if(! $driver->is_active, 403, __('errors.account_disabled'));

        return $driver;
    }

    /** @return Builder<Order> */
    private function base(Driver $driver): Builder
    {
        return Order::query()
            ->withoutTenancy()
            ->where('store_id', $driver->store_id)
            ->where('fulfillment_type', 'delivery');
    }

    private function notFound(): JsonResponse
    {
        return response()->json(['message' => __('errors.not_found'), 'error_code' => 'NOT_FOUND'], 404);
    }
}
