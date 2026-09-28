<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Domain\Booking\BookingStatus;
use App\Models\Booking;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Merchant-side booking management (spec §13, §19).
 *
 * Status changes go through the state machine, so an invalid transition is
 * rejected here exactly as it would be anywhere else.
 */
class BookingController extends MerchantController
{
    /**
     * GET /merchant/bookings?date=&status=&from=&to=
     */
    public function index(Request $request): JsonResponse
    {
        $store = $this->merchantStore();

        $data = $request->validate([
            'date' => ['sometimes', 'date_format:Y-m-d'],
            'from' => ['sometimes', 'date_format:Y-m-d'],
            'to' => ['sometimes', 'date_format:Y-m-d'],
            'status' => ['sometimes', Rule::in(array_column(BookingStatus::cases(), 'value'))],
            'staff_id' => ['sometimes', 'integer'],
        ]);

        $query = Booking::query()
            ->where('store_id', $store->id)
            ->with(['service', 'staff', 'branch', 'customer.user']);

        // Dates arrive as store-local days; the column is UTC.
        if (isset($data['date'])) {
            $day = CarbonImmutable::parse($data['date'], $store->timezone);
            $query->whereBetween('starts_at', [$day->startOfDay()->utc(), $day->endOfDay()->utc()]);
        } elseif (isset($data['from'], $data['to'])) {
            $query->whereBetween('starts_at', [
                CarbonImmutable::parse($data['from'], $store->timezone)->startOfDay()->utc(),
                CarbonImmutable::parse($data['to'], $store->timezone)->endOfDay()->utc(),
            ]);
        }

        if (isset($data['status'])) {
            $query->where('booking_status', $data['status']);
        }

        if (isset($data['staff_id'])) {
            $query->where('staff_id', $data['staff_id']);
        }

        $locale = app()->getLocale();

        return response()->json([
            'data' => $query->orderBy('starts_at')->paginate(50)->through(fn (Booking $b) => [
                'id' => $b->id,
                'reference' => $b->reference,
                'status' => $b->booking_status->value,
                'starts_at' => $b->starts_at->setTimezone($store->timezone)->toIso8601String(),
                'ends_at' => $b->ends_at->setTimezone($store->timezone)->toIso8601String(),
                'time' => $b->starts_at->setTimezone($store->timezone)->format('H:i'),
                'duration_minutes' => $b->duration_minutes,
                'price' => (float) $b->price,
                'payment_status' => $b->payment_status,
                'service' => $b->service?->displayName($locale),
                'staff' => $b->staff?->name,
                'branch' => $b->branch?->displayName($locale),
                // The merchant DOES see the customer's phone — they need to
                // call about a late arrival. This is their own customer.
                'customer' => [
                    'name' => $b->customer?->fullName() ?? $b->guest_name,
                    'phone' => $b->customer?->user?->phone ?? $b->guest_phone,
                ],
                'notes' => $b->customer_notes,
                // Which buttons the dashboard should render.
                'allowed_transitions' => array_map(
                    fn (BookingStatus $s) => $s->value,
                    $b->booking_status->allowedTransitions(),
                ),
            ]),
        ]);
    }

    /**
     * POST /merchant/bookings/{id}/status  { "status": "checked_in" }
     */
    public function updateStatus(int $id, Request $request): JsonResponse
    {
        $data = $request->validate([
            'status' => ['required', Rule::in(array_column(BookingStatus::cases(), 'value'))],
            'reason' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);

        $booking = Booking::findOrFail($id);
        $this->authorize('update', $booking);

        // An invalid transition throws InvalidStatusTransition, rendered as 422
        // with error_code INVALID_STATUS_TRANSITION (bootstrap/app.php).
        $booking->transitionTo(
            BookingStatus::from($data['status']),
            'merchant',
            $request->user()->id,
            $data['reason'] ?? null,
        );

        return response()->json([
            'id' => $booking->id,
            'status' => $booking->booking_status->value,
            'allowed_transitions' => array_map(
                fn (BookingStatus $s) => $s->value,
                $booking->booking_status->allowedTransitions(),
            ),
        ]);
    }
}
