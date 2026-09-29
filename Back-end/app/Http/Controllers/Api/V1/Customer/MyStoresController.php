<?php

namespace App\Http\Controllers\Api\V1\Customer;

use App\Domain\Booking\BookingStatus;
use App\Domain\Discovery\StoreResolver;
use App\Http\Controllers\Controller;
use App\Models\Booking;
use App\Models\CustomerStore;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * ============================================================================
 * MY STORES — the entire customer home screen (spec §5, §46)
 *
 *   Good morning, Abdulaziz
 *
 *   My Stores
 *   ┌────────────────────────┐   ┌────────────────────────┐
 *   │ Glow Beauty            │   │ ABC Spa                │
 *   │ Next appointment       │   │ Last visit             │
 *   │ Tomorrow • 7:00 PM     │   │ 5 days ago             │
 *   │ [View Store]           │   │ [Book Again]           │
 *   └────────────────────────┘   └────────────────────────┘
 *
 * This endpoint returns ONLY stores the customer personally added by scanning a
 * QR or opening a merchant's link. There is no sibling endpoint that returns
 * anything else — no search, no nearby, no recommendations, no categories.
 * Wasla is not a marketplace.
 * ============================================================================
 */
class MyStoresController extends Controller
{
    public function __construct(private readonly StoreResolver $resolver) {}

    /**
     * GET /me/stores
     */
    public function index(Request $request): JsonResponse
    {
        $customer = $request->user()->customer;

        if ($customer === null) {
            return response()->json(['data' => []]);
        }

        $links = CustomerStore::query()
            ->where('customer_id', $customer->id)
            ->where('is_hidden', false)
            ->with(['store' => fn ($q) => $q->with('merchant', 'activeBranches.schedules')])
            ->orderByDesc('last_visited_at')
            ->get()
            // A store whose merchant was suspended should quietly drop out of
            // the list rather than 404 when tapped.
            ->filter(fn (CustomerStore $link) => $link->store?->isReachable())
            ->values();

        // One query for every card's appointment info, rather than one per card.
        $nextByStore = $this->nextAppointments($customer->id, $links->pluck('store_id')->all());
        $lastByStore = $this->lastVisits($customer->id, $links->pluck('store_id')->all());

        $locale = app()->getLocale();

        return response()->json([
            'data' => $links->map(function (CustomerStore $link) use ($nextByStore, $lastByStore, $locale) {
                $store = $link->store;
                $next = $nextByStore[$store->id] ?? null;
                $last = $lastByStore[$store->id] ?? null;

                return [
                    'token' => $store->public_token,
                    'name' => $store->displayName($locale),
                    // The home card shows logo + name + description and nothing
                    // else, so the description has to come down with the list.
                    'description' => $locale === 'en'
                        ? ($store->description_en ?: $store->description_ar)
                        : $store->description_ar,
                    'logo' => $store->logo_path,
                    'brand_color' => $store->brand_color,
                    'type' => $store->business_type,
                    // Open/closed badge on the home card.
                    'is_open' => $store->isOpenNow(),
                    'added_via' => $link->added_via,

                    // Drives which card variant the app shows.
                    'next_appointment' => $next === null ? null : [
                        'id' => $next->id,
                        'reference' => $next->reference,
                        'starts_at' => $next->starts_at->setTimezone($store->timezone)->toIso8601String(),
                        'service' => $next->service?->displayName($locale),
                    ],
                    'last_visit_at' => $last?->setTimezone($store->timezone)->toIso8601String(),
                ];
            }),
        ]);
    }

    /**
     * POST /me/stores  { "token": "8F72K" }
     *
     * Called after a scan, and by the "enter store code" fallback when iOS
     * deferred deep linking misses (ARCHITECTURE.md §8.3).
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string', 'max:20'],
            'added_via' => ['sometimes', 'in:qr,deep_link,booking'],
        ]);

        $store = $this->resolver->resolve($data['token']);

        if ($store === null) {
            return response()->json([
                'message' => __('errors.invalid_store_code'),
                'error_code' => 'STORE_NOT_FOUND',
            ], 404);
        }

        $customer = $request->user()->customer;

        $isNew = $this->resolver->addToMyStores($store, $customer, $data['added_via'] ?? 'qr');
        $this->resolver->recordAccess($store, $request, $customer);

        return response()->json([
            'token' => $store->public_token,
            'name' => $store->displayName(app()->getLocale()),
            'newly_added' => $isNew,
        ], $isNew ? 201 : 200);
    }

    /**
     * DELETE /me/stores/{token}
     *
     * Hides rather than deletes: the customer's booking history with that
     * merchant must survive, and re-scanning brings the card back.
     */
    public function destroy(string $token, Request $request): JsonResponse
    {
        $customer = $request->user()->customer;

        $link = CustomerStore::query()
            ->where('customer_id', $customer->id)
            ->whereHas('store', fn ($q) => $q->where('public_token', strtoupper($token)))
            ->first();

        if ($link === null) {
            return response()->json([
                'message' => __('errors.not_found'),
                'error_code' => 'NOT_FOUND',
            ], 404);
        }

        $link->forceFill(['is_hidden' => true])->save();

        return response()->json(['message' => __('booking.store_removed')]);
    }

    /**
     * @param  array<int, int>  $storeIds
     * @return array<int, Booking>
     */
    private function nextAppointments(int $customerId, array $storeIds): array
    {
        if ($storeIds === []) {
            return [];
        }

        return Booking::query()
            ->withoutTenancy()
            ->where('customer_id', $customerId)
            ->whereIn('store_id', $storeIds)
            ->upcoming()
            ->with('service')
            ->orderBy('starts_at')
            ->get()
            // First per store wins — the list is already sorted by time.
            ->unique('store_id')
            ->keyBy('store_id')
            ->all();
    }

    /**
     * @param  array<int, int>  $storeIds
     * @return array<int, \Carbon\CarbonImmutable>
     */
    private function lastVisits(int $customerId, array $storeIds): array
    {
        if ($storeIds === []) {
            return [];
        }

        return Booking::query()
            ->withoutTenancy()
            ->where('customer_id', $customerId)
            ->whereIn('store_id', $storeIds)
            ->where('booking_status', BookingStatus::Completed->value)
            ->orderByDesc('starts_at')
            ->get(['id', 'store_id', 'starts_at'])
            ->unique('store_id')
            ->mapWithKeys(fn (Booking $b) => [$b->store_id => $b->starts_at])
            ->all();
    }
}
