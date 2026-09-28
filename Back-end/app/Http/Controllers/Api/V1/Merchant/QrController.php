<?php

namespace App\Http\Controllers\Api\V1\Merchant;

use App\Domain\Discovery\QrCodeService;
use App\Models\QrScan;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Storage;

/** The merchant's QR code and its analytics (spec §24, §25). */
class QrController extends MerchantController
{
    public function __construct(TenantContext $tenant, private readonly QrCodeService $qr)
    {
        parent::__construct($tenant);
    }

    /**
     * GET /merchant/qr
     */
    public function show(): JsonResponse
    {
        $store = $this->merchantStore();
        $qr = $store->qrCode ?? $this->qr->generate($store);

        return response()->json([
            'token' => $store->public_token,
            'deep_link' => $store->deepLink(),
            'image_url' => $qr->image_path ? Storage::disk('public')->url($qr->image_path) : null,
            'download_svg_url' => url('/api/v1/merchant/qr/svg'),
            'version' => $qr->version,
            'analytics' => [
                'total_scans' => (int) $qr->scan_count,
                'last_scanned_at' => $qr->last_scanned_at?->toIso8601String(),
                'unique_customers' => QrScan::where('store_id', $store->id)
                    ->whereNotNull('customer_id')->distinct('customer_id')->count('customer_id'),
                'bookings_from_qr' => QrScan::where('store_id', $store->id)
                    ->whereNotNull('resulted_in_booking_id')->count(),
            ],
        ]);
    }

    /**
     * GET /merchant/qr/svg — vector, for printing at any size.
     */
    public function svg(): Response
    {
        return response($this->qr->svg($this->merchantStore()), 200, [
            'Content-Type' => 'image/svg+xml',
            'Content-Disposition' => 'attachment; filename="wasla-qr.svg"',
        ]);
    }

    /**
     * POST /merchant/qr/regenerate — issues a NEW token (spec §24).
     *
     * Destructive by design: every printed code stops working. The dashboard
     * must warn before calling this.
     */
    public function regenerate(): JsonResponse
    {
        $store = $this->merchantStore();
        $qr = $this->qr->regenerate($store);

        return response()->json([
            'message' => __('merchant.qr_regenerated'),
            'token' => $store->fresh()->public_token,
            'deep_link' => $store->fresh()->deepLink(),
            'version' => $qr->version,
        ]);
    }
}
