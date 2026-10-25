<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Domain\Booking\BookingStatus;
use App\Models\Booking;
use App\Models\Order;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Pagination\LengthAwarePaginator;

/**
 * The merchant's customer list (spec §24): everyone who has booked OR ordered
 * at this store, with the history a merchant needs before giving someone a
 * prime slot or trusting a large order. Bookings and orders are aggregated
 * separately (different tables, different notions of "completed") and merged
 * per customer — a restaurant with no bookings still sees every customer who
 * ordered, and a salon that also sells still sees both.
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

        /** @var array<string, array<string, mixed>> $rows keyed by customer id or guest phone */
        $rows = [];
        $slot = function (?int $customerId, ?string $phone, ?string $name) use (&$rows): array|string {
            $key = $customerId !== null ? 'c:'.$customerId : 'p:'.($phone ?? '');
            $rows[$key] ??= [
                'customer_id' => $customerId,
                'name' => null,
                'phone' => null,
                'total_bookings' => 0,
                'total_orders' => 0,
                'completed' => 0,
                'no_shows' => 0,
                'cancelled' => 0,
                'total_spent' => 0.0,
                'last_visit' => null,
            ];
            $rows[$key]['name'] = $rows[$key]['name'] ?: ($name ?: null);
            $rows[$key]['phone'] = $rows[$key]['phone'] ?: $phone;

            return $key;
        };
        $later = fn (?string $a, ?string $b): ?string => ($a === null || ($b !== null && $b > $a)) ? $b : $a;

        // ---- bookings ----------------------------------------------------------
        $bookings = Booking::query()
            ->where('bookings.store_id', $store->id)
            ->leftJoin('customers', 'customers.id', '=', 'bookings.customer_id')
            ->leftJoin('users', 'users.id', '=', 'customers.user_id')
            ->selectRaw('
                bookings.customer_id,
                MAX(COALESCE(CONCAT_WS(" ", customers.first_name, customers.last_name), bookings.guest_name)) as name,
                MAX(COALESCE(users.phone, bookings.guest_phone)) as phone,
                COUNT(*) as total_bookings,
                SUM(bookings.booking_status = ?) as completed,
                SUM(bookings.booking_status = ?) as no_shows,
                SUM(bookings.booking_status = ?) as cancelled,
                MAX(bookings.starts_at) as last_visit,
                SUM(CASE WHEN bookings.booking_status = ? THEN bookings.price ELSE 0 END) as total_spent
            ', [
                BookingStatus::Completed->value,
                BookingStatus::NoShow->value,
                BookingStatus::Cancelled->value,
                BookingStatus::Completed->value,
            ])
            // Registered customers group by customer_id; guest bookings have no
            // customer_id at all, so they are distinguished by phone instead.
            ->groupBy('bookings.customer_id', 'bookings.guest_phone')
            ->get();

        foreach ($bookings as $b) {
            $key = $slot($b->customer_id !== null ? (int) $b->customer_id : null, $b->phone, trim((string) $b->name));
            $r = &$rows[$key];
            $r['total_bookings'] += (int) $b->total_bookings;
            $r['completed'] += (int) $b->completed;
            $r['no_shows'] += (int) $b->no_shows;
            $r['cancelled'] += (int) $b->cancelled;
            $r['total_spent'] += (float) $b->total_spent;
            $r['last_visit'] = $later($r['last_visit'], $b->last_visit);
            unset($r);
        }

        // ---- orders ------------------------------------------------------------
        $orders = Order::query()
            ->where('orders.store_id', $store->id)
            ->leftJoin('customers', 'customers.id', '=', 'orders.customer_id')
            ->leftJoin('users', 'users.id', '=', 'customers.user_id')
            ->selectRaw('
                orders.customer_id,
                MAX(COALESCE(NULLIF(CONCAT_WS(" ", customers.first_name, customers.last_name), ""), users.name)) as name,
                MAX(users.phone) as phone,
                COUNT(*) as total_orders,
                SUM(orders.status = "completed") as completed,
                SUM(orders.status IN ("cancelled", "rejected")) as cancelled,
                MAX(orders.created_at) as last_visit,
                SUM(CASE WHEN orders.status = "completed" THEN orders.total ELSE 0 END) as total_spent
            ')
            ->groupBy('orders.customer_id')
            ->get();

        foreach ($orders as $o) {
            $key = $slot($o->customer_id !== null ? (int) $o->customer_id : null, $o->phone, trim((string) $o->name));
            $r = &$rows[$key];
            $r['total_orders'] += (int) $o->total_orders;
            $r['completed'] += (int) $o->completed;
            $r['cancelled'] += (int) $o->cancelled;
            $r['total_spent'] += (float) $o->total_spent;
            $r['last_visit'] = $later($r['last_visit'], $o->last_visit);
            unset($r);
        }

        $list = collect($rows)->values();

        if (isset($data['search'])) {
            $term = mb_strtolower($data['search']);
            $list = $list->filter(fn ($r) => str_contains(mb_strtolower((string) $r['name']), $term)
                || str_contains((string) $r['phone'], $term));
        }

        $list = $list
            ->sortByDesc('last_visit')
            ->values()
            ->map(fn ($r) => [...$r, 'total_spent' => round((float) $r['total_spent'], 2)]);

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
