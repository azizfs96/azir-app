<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Domain\Booking\BookingStatus;
use App\Domain\Merchant\MerchantOnboardingService;
use App\Models\Booking;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;

/**
 * GET /merchant/dashboard (spec §13).
 *
 *   Today
 *   24 Bookings · 18 Confirmed · 4 Completed · 1 Cancelled · 1 No-show
 *   Revenue SAR 4,850
 *   Upcoming  10:00 Sara · 11:30 Reem · 13:00 Ahmed
 */
class DashboardController extends MerchantController
{
    public function __construct(
        TenantContext $tenant,
        private readonly MerchantOnboardingService $onboarding,
    ) {
        parent::__construct($tenant);
    }

    public function index(): JsonResponse
    {
        $store = $this->merchantStore();
        $summary = $this->onboarding->dashboardFor($store);
        $now = CarbonImmutable::now($store->timezone);

        $upcoming = Booking::query()
            ->where('store_id', $store->id)
            ->where('starts_at', '>=', $now->utc())
            ->whereIn('booking_status', [
                BookingStatus::Pending->value,
                BookingStatus::Confirmed->value,
                BookingStatus::CheckedIn->value,
            ])
            ->with(['service', 'staff', 'customer.user'])
            ->orderBy('starts_at')
            ->limit(10)
            ->get();

        $locale = app()->getLocale();

        return response()->json([
            ...$summary,
            'store' => [
                'token' => $store->public_token,
                'name' => $store->displayName($locale),
                'is_published' => (bool) $store->is_published,
                'deep_link' => $store->deepLink(),
            ],
            'upcoming' => $upcoming->map(fn (Booking $booking) => [
                'id' => $booking->id,
                'reference' => $booking->reference,
                'time' => $booking->starts_at->setTimezone($store->timezone)->format('H:i'),
                'starts_at' => $booking->starts_at->setTimezone($store->timezone)->toIso8601String(),
                'status' => $booking->booking_status->value,
                'service' => $booking->service?->displayName($locale),
                'staff' => $booking->staff?->name,
                'customer' => $booking->customer?->fullName() ?? $booking->guest_name,
            ]),
        ]);
    }
}
