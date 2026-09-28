<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Role gate for the four API namespaces (spec §34).
 *
 * Usage: ->middleware('role:merchant_owner,merchant_staff')
 *
 * This is coarse routing-level separation — customer endpoints are not reachable
 * by merchant tokens and vice versa. Per-record authorization is still the job
 * of policies; this only decides who may knock on the door.
 */
class EnsureRole
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $user = $request->user();

        if ($user === null || ! in_array($user->role, $roles, true)) {
            return response()->json([
                'message' => __('errors.forbidden'),
                'error_code' => 'FORBIDDEN',
            ], 403);
        }

        if (! $user->is_active) {
            return response()->json([
                'message' => __('errors.account_disabled'),
                'error_code' => 'ACCOUNT_DISABLED',
            ], 403);
        }

        return $next($request);
    }
}
