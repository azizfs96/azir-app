<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Domain\Booking\BookingService;
use App\Domain\Booking\Exceptions\SlotNoLongerAvailable;
use App\Domain\Discovery\StoreResolver;
use App\Http\Controllers\Controller;
use App\Http\Resources\BookingResource;
use App\Models\Booking;
use App\Models\Branch;
use App\Models\CustomerStore;
use App\Models\Service;
use App\Models\Staff;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * Customer bookings (spec §36, §41).
 *
 *   Scan QR -> Store -> Service -> [Staff] -> Date -> Time -> Confirmed
 *
 * Online payment is out of scope for the MVP, so confirmation is the last step
 * and everything is paid at the store.
 */
class BookingController extends Controller
{
    public function __construct(
        private readonly BookingService $bookings,
        private readonly StoreResolver $resolver,
    ) {}

    /**
     * GET /bookings?filter=upcoming|past
     */
    public function index(Request $request): AnonymousResourceCollection
    {
        $customer = $request->user()->customer;
        $filter = $request->query('filter', 'upcoming');

        /*
         * Optional store_token narrows the list to ONE merchant.
         *
         * That is what lets a store page show "your history here" without
         * leaking anything: the token identifies which merchant, and the
         * customer_id constraint below still does the actual authorization.
         */
        $storeToken = $request->query('store_token');

        $query = Booking::query()
            // A customer's bookings span many merchants by definition, so the
            // tenant scope must not apply — customer_id is the constraint here.
            ->withoutTenancy()
            ->where('customer_id', $customer?->id)
            ->with(['store', 'service', 'branch', 'staff']);

        if (is_string($storeToken) && $storeToken !== '') {
            $query->whereHas(
                'store',
                fn ($q) => $q->where('public_token', strtoupper($storeToken)),
            );
        }

        $query = $filter === 'past'
            ? $query->where('starts_at', '<', CarbonImmutable::now())->orderByDesc('starts_at')
            : $query->upcoming()->orderBy('starts_at');

        return BookingResource::collection($query->paginate(20));
    }

    /**
     * GET /bookings/{id}
     */
    public function show(int $id, Request $request): BookingResource|JsonResponse
    {
        $booking = $this->findForCustomer($id, $request);

        return $booking === null
            ? $this->notFound()
            : new BookingResource($booking);
    }

    /**
     * POST /bookings
     *
     * Every id in the payload is resolved THROUGH the store token, so a client
     * cannot mix a service from one merchant with a stylist from another.
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'store_token' => ['required', 'string', 'max:20'],
            'service_id' => ['required', 'integer'],
            'starts_at' => ['required', 'date'],
            'branch_id' => ['sometimes', 'nullable', 'integer'],
            'staff_id' => ['sometimes', 'nullable', 'integer'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:500'],
        ]);

        $store = $this->resolver->resolve($data['store_token']);

        if ($store === null) {
            return response()->json([
                'message' => __('errors.store_unavailable'),
                'error_code' => 'STORE_NOT_FOUND',
            ], 404);
        }

        $service = Service::where('store_id', $store->id)->where('is_active', true)
            ->find($data['service_id']);

        if ($service === null) {
            return response()->json([
                'message' => __('errors.not_found'),
                'error_code' => 'SERVICE_NOT_FOUND',
            ], 404);
        }

        $branch = isset($data['branch_id'])
            ? Branch::where('store_id', $store->id)->where('is_active', true)->find($data['branch_id'])
            : $store->defaultBranch();

        $settings = $store->bookingSettings;

        /*
         * Honour the merchant's configuration on the WRITE path too.
         *
         * If staff_selection is off, a client-supplied staff_id is ignored
         * rather than obeyed — otherwise a customer could hand-pick a stylist
         * the merchant deliberately chose not to expose.
         */
        $staff = null;

        if ($settings?->staff_selection && isset($data['staff_id'])) {
            $staff = Staff::where('store_id', $store->id)
                ->bookable()
                ->with(['schedules', 'services'])
                ->find($data['staff_id']);

            if ($staff === null) {
                return response()->json([
                    'message' => __('errors.not_found'),
                    'error_code' => 'STAFF_NOT_FOUND',
                ], 404);
            }
        }

        $customer = $request->user()->customer;
        $startsAt = CarbonImmutable::parse($data['starts_at'])->setTimezone($store->timezone);

        try {
            $booking = $this->bookings->create(
                store: $store,
                service: $service,
                startsAt: $startsAt,
                branch: $branch,
                requestedStaff: $staff,
                customer: $customer,
                attributes: [
                    // Notes are only accepted if the merchant asked for them.
                    'customer_notes' => $settings?->customer_notes ? ($data['notes'] ?? null) : null,
                    'source' => 'app',
                ],
            );
        } catch (SlotNoLongerAvailable $e) {
            return response()->json([
                'message' => __('errors.slot_taken'),
                'error_code' => 'SLOT_TAKEN',
            ], 409);
        }

        // Booking a store implies it belongs in My Stores.
        if ($customer !== null) {
            $this->resolver->addToMyStores($store, $customer, 'booking');

            CustomerStore::where('customer_id', $customer->id)
                ->where('store_id', $store->id)
                ->update(['last_booking_at' => CarbonImmutable::now()]);
        }

        return response()->json(
            new BookingResource($booking->load(['store', 'service', 'branch', 'staff'])),
            201,
        );
    }

    /**
     * POST /bookings/{id}/cancel (spec §21)
     */
    public function cancel(int $id, Request $request): JsonResponse
    {
        $booking = $this->findForCustomer($id, $request);

        if ($booking === null) {
            return $this->notFound();
        }

        $settings = $booking->store->bookingSettings;

        if (! $settings?->allow_cancellation) {
            return response()->json([
                'message' => __('errors.cancellation_not_allowed'),
                'error_code' => 'CANCELLATION_NOT_ALLOWED',
            ], 422);
        }

        if (! $booking->isCancellableByCustomer()) {
            return response()->json([
                'message' => __('errors.cancellation_deadline_passed'),
                'error_code' => 'CANCELLATION_DEADLINE_PASSED',
                'deadline_hours' => $settings->cancellation_deadline_hours,
            ], 422);
        }

        $booking->transitionTo(
            \App\Domain\Booking\BookingStatus::Cancelled,
            'customer',
            $request->user()->id,
            $request->input('reason'),
        );

        return response()->json([
            'message' => __('booking.cancelled'),
            'booking' => new BookingResource($booking->load(['store', 'service'])),
        ]);
    }

    /**
     * POST /bookings/{id}/reschedule (spec §22)
     */
    public function reschedule(int $id, Request $request): JsonResponse
    {
        $data = $request->validate([
            'starts_at' => ['required', 'date'],
            'staff_id' => ['sometimes', 'nullable', 'integer'],
        ]);

        $booking = $this->findForCustomer($id, $request);

        if ($booking === null) {
            return $this->notFound();
        }

        $settings = $booking->store->bookingSettings;

        if (! $settings?->allow_rescheduling) {
            return response()->json([
                'message' => __('errors.reschedule_not_allowed'),
                'error_code' => 'RESCHEDULE_NOT_ALLOWED',
            ], 422);
        }

        if (! $booking->isReschedulableByCustomer()) {
            return response()->json([
                'message' => __('errors.reschedule_deadline_passed'),
                'error_code' => 'RESCHEDULE_DEADLINE_PASSED',
            ], 422);
        }

        $staff = isset($data['staff_id']) && $settings->staff_selection
            ? Staff::where('store_id', $booking->store_id)->bookable()
                ->with(['schedules', 'services'])->find($data['staff_id'])
            : null;

        try {
            $booking = $this->bookings->reschedule(
                $booking,
                CarbonImmutable::parse($data['starts_at'])->setTimezone($booking->store->timezone),
                $staff,
                $request->user()->id,
            );
        } catch (SlotNoLongerAvailable $e) {
            return response()->json([
                'message' => __('errors.slot_unavailable'),
                'error_code' => 'SLOT_TAKEN',
            ], 409);
        }

        return response()->json([
            'message' => __('booking.rescheduled'),
            'booking' => new BookingResource($booking->load(['store', 'service', 'branch', 'staff'])),
        ]);
    }

    /**
     * Always scoped to the authenticated customer — never a bare find().
     */
    private function findForCustomer(int $id, Request $request): ?Booking
    {
        return Booking::query()
            ->withoutTenancy()
            ->where('customer_id', $request->user()->customer?->id)
            ->with(['store.bookingSettings', 'service', 'branch', 'staff'])
            ->find($id);
    }

    private function notFound(): JsonResponse
    {
        return response()->json([
            'message' => __('errors.not_found'),
            'error_code' => 'NOT_FOUND',
        ], 404);
    }
}
