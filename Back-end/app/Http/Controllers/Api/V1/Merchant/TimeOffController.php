<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Models\Booking;
use App\Models\Branch;
use App\Models\Staff;
use App\Models\TimeOff;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * ============================================================================
 * BLOCKED TIME / TIME OFF — the "emergency at 6 PM" feature
 *
 * The engine, the availability cache observer and the write-path validation
 * have honoured time_off rows since day one; this controller is the missing
 * door. It answers the question the weekly schedule cannot: "TODAY, from 6 to
 * 7, no bookings" — a one-off block on a DATE, not a recurring break on a
 * weekday.
 *
 * Targets exactly one of staff_id / branch_id (a stylist's errand vs the whole
 * branch closing for Eid) — the model enforces it, this validates it politely.
 *
 * AFFECTED BOOKINGS: creating a block does NOT touch existing bookings — they
 * were promises made to customers and cancelling them is a human decision. The
 * response lists every future booking inside the blocked window so the
 * dashboard can put them in front of the merchant instead of letting them be
 * discovered by an angry customer at the door.
 * ============================================================================
 */
class TimeOffController extends MerchantController
{
    /**
     * GET /merchant/time-off?staff_id=&branch_id=
     *
     * Upcoming blocks only — history is noise in a scheduling screen.
     */
    public function index(Request $request): JsonResponse
    {
        $data = $request->validate([
            'staff_id' => ['sometimes', 'integer'],
            'branch_id' => ['sometimes', 'integer'],
        ]);

        $store = $this->merchantStore();

        $rows = TimeOff::query()
            ->where('ends_at', '>', CarbonImmutable::now())
            ->when(isset($data['staff_id']), fn ($q) => $q->where('staff_id', $data['staff_id']))
            ->when(isset($data['branch_id']), fn ($q) => $q->where('branch_id', $data['branch_id']))
            ->orderBy('starts_at')
            ->limit(100)
            ->get();

        return response()->json([
            'data' => $rows->map(fn (TimeOff $off) => $this->serialize($off, $store->timezone)),
        ]);
    }

    /**
     * POST /merchant/time-off
     *
     * The dashboard sends a LOCAL date + clock times; the server owns the
     * timezone conversion, so a device in the wrong timezone cannot shift a
     * merchant's block. `to` at or before `from` rolls into the next day —
     * the same rule the engine applies to night shifts.
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'staff_id' => ['sometimes', 'nullable', 'integer'],
            'branch_id' => ['sometimes', 'nullable', 'integer'],
            'date' => ['required', 'date_format:Y-m-d'],
            'from' => ['required', 'date_format:H:i'],
            'to' => ['required', 'date_format:H:i'],
            'reason' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);

        $store = $this->merchantStore();

        $staffId = $data['staff_id'] ?? null;
        $branchId = $data['branch_id'] ?? null;

        if (($staffId === null) === ($branchId === null)) {
            return response()->json([
                'message' => __('merchant.time_off_target'),
                'error_code' => 'TIME_OFF_TARGET_INVALID',
            ], 422);
        }

        // Both lookups are store-scoped: a foreign id must read as not-found.
        if ($staffId !== null && ! Staff::where('store_id', $store->id)->whereKey($staffId)->exists()) {
            return response()->json([
                'message' => __('errors.not_found'), 'error_code' => 'NOT_FOUND',
            ], 404);
        }

        if ($branchId !== null && ! Branch::where('store_id', $store->id)->whereKey($branchId)->exists()) {
            return response()->json([
                'message' => __('errors.not_found'), 'error_code' => 'NOT_FOUND',
            ], 404);
        }

        $startsAt = CarbonImmutable::parse("{$data['date']} {$data['from']}", $store->timezone);
        $endsAt = CarbonImmutable::parse("{$data['date']} {$data['to']}", $store->timezone);

        // 00:00–00:00 is "the whole day"; 22:00–02:00 is a block past midnight.
        if ($endsAt->lessThanOrEqualTo($startsAt)) {
            $endsAt = $endsAt->addDay();
        }

        if ($endsAt->lessThanOrEqualTo(CarbonImmutable::now())) {
            return response()->json([
                'message' => __('merchant.time_off_past'),
                'error_code' => 'TIME_OFF_IN_PAST',
            ], 422);
        }

        $timeOff = TimeOff::create([
            'staff_id' => $staffId,
            'branch_id' => $branchId,
            'starts_at' => $startsAt->utc(),
            'ends_at' => $endsAt->utc(),
            'reason' => $data['reason'] ?? null,
        ]);

        // The ScheduleAvailabilityObserver has already bumped the availability
        // cache; from this instant customers stop being offered the window.
        return response()->json([
            'data' => $this->serialize($timeOff, $store->timezone),
            'affected_bookings' => $this->affectedBookings(
                $staffId, $branchId, $startsAt->utc(), $endsAt->utc(), $store->timezone,
            ),
        ], 201);
    }

    /**
     * DELETE /merchant/time-off/{id} — the errand got cancelled; the hours
     * reopen the moment the observer bumps the cache.
     */
    public function destroy(int $id): JsonResponse
    {
        $timeOff = TimeOff::findOrFail($id);
        $this->authorize('delete', $timeOff);

        $timeOff->delete();

        return response()->json(['message' => __('merchant.time_off_deleted')]);
    }

    /**
     * Future bookings sitting inside the blocked window.
     *
     * These stay VALID — blocking time never cancels a customer's booking.
     * They are returned so the merchant sees exactly who they now need to
     * call, reschedule, or serve anyway.
     *
     * @return array<int, array<string, mixed>>
     */
    private function affectedBookings(
        ?int $staffId,
        ?int $branchId,
        CarbonImmutable $startsAt,
        CarbonImmutable $endsAt,
        string $timezone,
    ): array {
        return Booking::query()
            ->when($staffId !== null, fn ($q) => $q->where('staff_id', $staffId))
            ->when($branchId !== null, fn ($q) => $q->where('branch_id', $branchId))
            ->blocking()
            ->overlapping($startsAt, $endsAt)
            ->with(['service:id,name_ar,name_en', 'customer:id,name'])
            ->orderBy('starts_at')
            ->limit(50)
            ->get()
            ->map(fn (Booking $booking) => [
                'id' => $booking->id,
                'reference' => $booking->reference,
                'starts_at' => $booking->starts_at->setTimezone($timezone)->toIso8601String(),
                'service' => $booking->service?->name_ar,
                'customer' => $booking->customer?->name,
            ])
            ->all();
    }

    /** @return array<string, mixed> */
    private function serialize(TimeOff $timeOff, string $timezone): array
    {
        return [
            'id' => $timeOff->id,
            'staff_id' => $timeOff->staff_id,
            'branch_id' => $timeOff->branch_id,
            'starts_at' => $timeOff->starts_at->setTimezone($timezone)->toIso8601String(),
            'ends_at' => $timeOff->ends_at->setTimezone($timezone)->toIso8601String(),
            'reason' => $timeOff->reason,
        ];
    }
}
