<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Domain\Ordering\OrderStatus;
use App\Http\Resources\OrderResource;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\OrderItem;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * GET /merchant/grocery/dashboard — the supermarket home screen.
 *
 * Orders, not bookings: today's board by status, revenue today / this week,
 * products running low, the best sellers of the month, and the orders that
 * need a hand right now. A handful of grouped queries — nothing per row.
 */
class GroceryDashboardController extends MerchantController
{
    private const LOW_STOCK_AT = 5;

    public function index(): JsonResponse
    {
        $store = $this->merchantStore();
        $tz = $store->timezone ?: 'Asia/Riyadh';
        $now = CarbonImmutable::now($tz);
        $dayStart = $now->startOfDay()->utc();
        $weekStart = $now->subDays(6)->startOfDay()->utc();
        $monthStart = $now->subDays(29)->startOfDay()->utc();

        $base = Order::query()->where('store_id', $store->id);

        // One GROUP BY for every "today" counter.
        $todayByStatus = (clone $base)
            ->where('created_at', '>=', $dayStart)
            ->select('status', DB::raw('COUNT(*) as c'))
            ->groupBy('status')
            ->pluck('c', 'status');

        $count = fn (string ...$statuses) => (int) collect($statuses)->sum(fn ($s) => $todayByStatus[$s] ?? 0);

        $revenueToday = (float) (clone $base)
            ->where('status', OrderStatus::Completed->value)
            ->where('completed_at', '>=', $dayStart)
            ->sum('total');

        $revenueWeek = (float) (clone $base)
            ->where('status', OrderStatus::Completed->value)
            ->where('completed_at', '>=', $weekStart)
            ->sum('total');

        // Revenue per day for the last 7 days (a tiny sparkline).
        $perDay = (clone $base)
            ->where('status', OrderStatus::Completed->value)
            ->where('completed_at', '>=', $weekStart)
            ->get(['completed_at', 'total'])
            ->groupBy(fn (Order $o) => $o->completed_at->setTimezone($tz)->toDateString())
            ->map(fn ($rows) => round((float) $rows->sum('total'), 2));

        $series = [];
        for ($i = 6; $i >= 0; $i--) {
            $day = $now->subDays($i)->toDateString();
            $series[] = ['date' => $day, 'revenue' => $perDay[$day] ?? 0.0];
        }

        $lowStock = MenuItem::query()
            ->where('store_id', $store->id)
            ->where('is_active', true)
            ->whereNotNull('stock_quantity')
            ->where('stock_quantity', '<=', self::LOW_STOCK_AT)
            ->orderBy('stock_quantity')
            ->limit(8)
            ->get(['id', 'name_ar', 'name_en', 'stock_quantity', 'image_path', 'unit']);

        $bestSellers = OrderItem::query()
            ->select('menu_item_id', 'name', DB::raw('SUM(quantity) as qty'), DB::raw('SUM(line_total) as revenue'))
            ->whereIn('order_id', (clone $base)
                ->where('status', OrderStatus::Completed->value)
                ->where('completed_at', '>=', $monthStart)
                ->select('id'))
            ->whereNotNull('menu_item_id')
            ->groupBy('menu_item_id', 'name')
            ->orderByDesc('qty')
            ->limit(5)
            ->get();

        $needsAction = (clone $base)
            ->whereIn('status', [OrderStatus::Placed->value, OrderStatus::Preparing->value, OrderStatus::OutForDelivery->value])
            ->with(['customer.user', 'items', 'driver'])
            ->orderBy('created_at')
            ->limit(8)
            ->get();

        $products = MenuItem::query()->where('store_id', $store->id)->where('is_active', true);
        $locale = app()->getLocale();

        return response()->json([
            'date' => $now->toDateString(),
            'store' => [
                'token' => $store->public_token,
                'name' => $store->displayName($locale),
                'is_published' => (bool) $store->is_published,
                'deep_link' => $store->deepLink(),
            ],
            'today' => [
                'new' => $count('placed'),
                'preparing' => $count('preparing', 'accepted', 'ready'),
                'out_for_delivery' => $count('out_for_delivery'),
                'delivered' => $count('completed'),
                'cancelled' => $count('cancelled', 'rejected'),
                'orders' => (int) $todayByStatus->sum(),
            ],
            'revenue' => [
                'today' => round($revenueToday, 2),
                'week' => round($revenueWeek, 2),
                'series' => $series,
            ],
            'catalog' => [
                'products' => (int) (clone $products)->count(),
                'out_of_stock' => (int) (clone $products)->where(fn ($q) => $q->where('is_available', false)->orWhere('stock_quantity', 0))->count(),
                'low_stock' => $lowStock->map(fn (MenuItem $item) => [
                    'id' => $item->id,
                    'name' => $item->displayName($locale),
                    'image' => $item->image_path,
                    'unit' => $item->unit,
                    'stock_quantity' => $item->stock_quantity,
                ]),
            ],
            'best_sellers' => $bestSellers->map(fn ($row) => [
                'item_id' => $row->menu_item_id,
                'name' => $row->name,
                'quantity' => (int) $row->qty,
                'revenue' => round((float) $row->revenue, 2),
            ]),
            'needs_action' => OrderResource::collection($needsAction),
        ]);
    }
}
