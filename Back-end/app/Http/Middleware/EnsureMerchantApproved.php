<?php

namespace App\Http\Middleware;

use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Blocks merchant API access unless the tenant is approved and not suspended
 * (spec §39: admin can suspend a merchant).
 *
 * Deliberately allows the onboarding routes through — a pending merchant must
 * still be able to complete setup and submit for approval (spec §11).
 */
class EnsureMerchantApproved
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function handle(Request $request, Closure $next): Response
    {
        $merchant = $this->tenant->merchant();

        if ($merchant === null) {
            return response()->json([
                'message' => __('errors.no_merchant_context'),
                'error_code' => 'NO_MERCHANT_CONTEXT',
            ], 403);
        }

        if (! $merchant->isOperational()) {
            return response()->json([
                'message' => __('errors.merchant_not_active'),
                'error_code' => 'MERCHANT_NOT_ACTIVE',
                'status' => $merchant->status,
            ], 403);
        }

        return $next($request);
    }
}
