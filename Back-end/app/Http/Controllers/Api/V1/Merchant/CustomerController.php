<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Domain\Booking\BookingStatus;
use App\Models\Booking;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * ============================================================================
 * MERCHANT CUSTOMERS (spec §12)
 *
 * A customer belongs to the PLATFORM, not to a merchant — one identity across
 * every store they have ever scanned. So "my customers" is not an ownership
 * query; it is DERIVED from the bookings this merchant has actually received.
 *
 * That distinction is the whole point of §46: a merchant sees the people who
 * came to them, never the platform's customer list.
 * ============================================================================
 */
class CustomerController extends MerchantController
{
    public function index(Request $request): JsonResponse
    {
        $store = $this->merchantStore();

        $data = $request->validate([
            'search' => ['sometimes', 'string', 'max:80'],
        ]);

        /*
         * Aggregated from bookings in one query rather than N+1 over customers.
         *
         * Grouping by the customer's user row also folds in guest bookings,
         * which have no customer_id at all.
         */
        $query = Booking::query()
            ->where('bookings.store_id', $store->id)
            ->leftJoin('customers', 'customers.id', '=', 'bookings.customer_id')
            ->leftJoin('users', 'users.id', '=', 'customers.user_id')
            /*
             * Name and phone are wrapped in MAX() rather than grouped.
             *
             * MySQL runs with ONLY_FULL_GROUP_BY, so every non-aggregated
             * column must appear in GROUP BY — and grouping on the aliases
             * would silently split one person across rows if they ever booked
             * under a slightly different name. Aggregating instead keeps the
             * grouping keys to the two things that actually identify someone.
             */
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
            ->groupBy('bookings.customer_id', 'bookings.guest_phone');

        if (isset($data['search'])) {
            $term = '%'.$data['search'].'%';
            $query->having(fn ($q) => $q->where('name', 'like', $term)->orWhere('phone', 'like', $term));
        }

        return response()->json([
            'data' => $query
                ->orderByDesc('last_visit')
                ->paginate(30)
                ->through(fn ($row) => [
                    'customer_id' => $row->customer_id,
                    'name' => $row->name ?: null,
                    'phone' => $row->phone,
                    'total_bookings' => (int) $row->total_bookings,
                    'completed' => (int) $row->completed,
                    // A merchant genuinely needs this before giving someone a
                    // prime Thursday-evening slot.
                    'no_shows' => (int) $row->no_shows,
                    'cancelled' => (int) $row->cancelled,
                    'total_spent' => (float) $row->total_spent,
                    'last_visit' => $row->last_visit,
                ]),
        ]);
    }
}
