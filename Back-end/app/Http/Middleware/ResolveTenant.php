<?php

namespace App\Http\Middleware;

use App\Models\User;
use App\Support\TenantContext;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Layer 1 of tenant isolation (ARCHITECTURE.md §4; spec §26, §35).
 *
 * ============================================================================
 * This middleware is the ONLY place the active tenant is ever decided.
 *
 * It reads merchant_id from the AUTHENTICATED USER. It does not look at the
 * request body, the query string, a route parameter, or a header — because
 * "Never trust tenant IDs sent from the frontend" is only true if there is
 * exactly one code path capable of trusting one.
 * ============================================================================
 */
class ResolveTenant
{
    public function __construct(private readonly TenantContext $tenant) {}

    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if ($user instanceof User && $user->isMerchantUser() && $user->merchant_id !== null) {
            // Loading the relation (rather than trusting the raw id) also gives
            // downstream policies the merchant's status without a second query.
            $this->tenant->setTenant($user->merchant);
        }

        return $next($request);
    }
}
