<?php

namespace App\Http\Controllers\Api\V1\Admin;

use App\Domain\Booking\BookingStatus;
use App\Http\Controllers\Controller;
use App\Models\Booking;
use App\Models\Customer;
use App\Models\Merchant;
use App\Models\QrScan;
use App\Models\Store;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;

/**
 * Platform metrics (spec §39).
 *
 * Deliberately small — §40 rules out advanced analytics for the MVP. These are
 * the numbers that tell you whether the platform is working at all.
 */
class MetricsController extends Controller
{
    public function index(): JsonResponse
    {
        $now = CarbonImmutable::now();
        $monthStart = $now->startOfMonth();

        $merchantsByStatus = Merchant::query()
            ->selectRaw('status, COUNT(*) as total')
            ->groupBy('status')
            ->pluck('total', 'status');

        return response()->json([
            'merchants' => [
                'total' => (int) $merchantsByStatus->sum(),
                // The approval queue is the number an admin acts on.
                'pending' => (int) ($merchantsByStatus['pending'] ?? 0),
                'approved' => (int) ($merchantsByStatus['approved'] ?? 0),
                'suspended' => (int) ($merchantsByStatus['suspended'] ?? 0),
                'rejected' => (int) ($merchantsByStatus['rejected'] ?? 0),
            ],
            'stores' => [
                'total' => Store::query()->withoutTenancy()->count(),
                'published' => Store::query()->withoutTenancy()->where('is_published', true)->count(),
            ],
            'customers' => [
                'total' => Customer::count(),
                'new_this_month' => Customer::where('created_at', '>=', $monthStart)->count(),
            ],
            'bookings' => [
                'total' => Booking::query()->withoutTenancy()->count(),
                'this_month' => Booking::query()->withoutTenancy()
                    ->where('created_at', '>=', $monthStart)->count(),
                'completed' => Booking::query()->withoutTenancy()
                    ->where('booking_status', BookingStatus::Completed->value)->count(),
                'cancelled' => Booking::query()->withoutTenancy()
                    ->where('booking_status', BookingStatus::Cancelled->value)->count(),
            ],
            // The QR funnel is the core product hypothesis (spec §25).
            'qr' => [
                'total_scans' => QrScan::query()->withoutTenancy()->count(),
                'scans_this_month' => QrScan::query()->withoutTenancy()
                    ->where('scanned_at', '>=', $monthStart)->count(),
            ],
        ]);
    }
}
