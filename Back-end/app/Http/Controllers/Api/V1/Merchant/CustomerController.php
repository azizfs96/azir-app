<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Domain\Booking\BookingStatus;
use App\Models\Booking;
use App\Models\CustomerStore;
use App\Models\Order;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Pagination\LengthAwarePaginator;

/**
 * The merchant's customer list (spec §24).
 *
 * A customer of a store is someone who has the store in THEIR list — they
 * scanned its QR (or opened its link / booked / ordered) and it sits on their
 * home screen. That is the whole definition: the moment a person removes the
 * store from their list (is_hidden) they leave this list too, and re-scanning
 * brings them back. Order and booking history is attached per customer so the
 * merchant can see who actually buys — but it never adds anyone by itself.
 */
class CustomerController extends MerchantController
{
    public function index(Request $request): JsonResponse
    {
        $store = $this->merchantStore();

        $data = $request->validate([
            'search' => ['sometimes', 'string', 'max:80'],
            'page' => ['sometimes', 'integer', 'min:1'],
        ]);

        // ---- the base set: everyone who currently has this store in My Stores --
        $links = CustomerStore::query()
            ->where('customer_stores.store_id', $store->id)
            ->where('customer_stores.is_hidden', false)
            ->join('customers', 'customers.id', '=', 'customer_stores.customer_id')
            ->join('users', 'users.id', '=', 'customers.user_id')
            ->selectRaw('
                customer_stores.customer_id,
                COALESCE(NULLIF(CONCAT_WS(" ", customers.first_name, customers.last_name), ""), users.name) as name,
                users.phone,
                customer_stores.added_via,
                customer_stores.first_added_at,
                customer_stores.last_visited_at
            ')
            ->get();

        if ($links->isEmpty()) {
            return response()->json(['data' => new LengthAwarePaginator([], 0, 30, 1)]);
        }

        $ids = $links->pluck('customer_id')->all();

        // ---- history, attached per customer ----------------------------------
        $orders = Order::query()
            ->where('store_id', $store->id)
            ->whereIn('customer_id', $ids)
            ->selectRaw('
                customer_id,
                COUNT(*) as total_orders,
                SUM(status = "completed") as completed,
                SUM(status IN ("cancelled", "rejected")) as cancelled,
                MAX(created_at) as last_at,
                SUM(CASE WHEN status = "completed" THEN total ELSE 0 END) as spent
            ')
            ->groupBy('customer_id')
            ->get()
            ->keyBy('customer_id');

        $bookings = Booking::query()
            ->where('store_id', $store->id)
            ->whereIn('customer_id', $ids)
            ->selectRaw('
                customer_id,
                COUNT(*) as total_bookings,
                SUM(booking_status = ?) as completed,
                SUM(booking_status = ?) as no_shows,
                SUM(booking_status = ?) as cancelled,
                MAX(starts_at) as last_at,
                SUM(CASE WHEN booking_status = ? THEN price ELSE 0 END) as spent
            ', [
                BookingStatus::Completed->value,
                BookingStatus::NoShow->value,
                BookingStatus::Cancelled->value,
                BookingStatus::Completed->value,
            ])
            ->groupBy('customer_id')
            ->get()
            ->keyBy('customer_id');

        $later = fn (?string $a, ?string $b): ?string => ($a === null || ($b !== null && $b > $a)) ? $b : $a;

        $list = $links->map(function ($l) use ($orders, $bookings, $later) {
            $o = $orders->get($l->customer_id);
            $b = $bookings->get($l->customer_id);
            $lastVisit = $later((string) $l->last_visited_at ?: null, $o?->last_at);
            $lastVisit = $later($lastVisit, $b?->last_at);

            return [
                'customer_id' => (int) $l->customer_id,
                'name' => $l->name ?: null,
                'phone' => $l->phone,
                'added_via' => $l->added_via,
                'joined_at' => $l->first_added_at,
                'total_orders' => (int) ($o?->total_orders ?? 0),
                'total_bookings' => (int) ($b?->total_bookings ?? 0),
                'completed' => (int) ($o?->completed ?? 0) + (int) ($b?->completed ?? 0),
                'no_shows' => (int) ($b?->no_shows ?? 0),
                'cancelled' => (int) ($o?->cancelled ?? 0) + (int) ($b?->cancelled ?? 0),
                'total_spent' => round((float) ($o?->spent ?? 0) + (float) ($b?->spent ?? 0), 2),
                'last_visit' => $lastVisit,
            ];
        });

        if (isset($data['search'])) {
            $term = mb_strtolower($data['search']);
            $list = $list->filter(fn ($r) => str_contains(mb_strtolower((string) $r['name']), $term)
                || str_contains((string) $r['phone'], $term));
        }

        $list = $list->sortByDesc('last_visit')->values();

        $page = (int) ($data['page'] ?? 1);
        $perPage = 30;
        $paginator = new LengthAwarePaginator(
            $list->slice(($page - 1) * $perPage, $perPage)->values(),
            $list->count(),
            $perPage,
            $page,
            ['path' => $request->url(), 'query' => $request->query()],
        );

        return response()->json(['data' => $paginator]);
    }
}
