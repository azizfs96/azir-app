<?php

use App\Domain\Booking\Exceptions\InvalidStatusTransition;
use App\Domain\Booking\Exceptions\SlotNoLongerAvailable;
use App\Http\Middleware\EnsureMerchantApproved;
use App\Http\Middleware\EnsureRole;
use App\Http\Middleware\ResolveTenant;
use App\Http\Middleware\SetLocale;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
        apiPrefix: 'api/v1',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'tenant' => ResolveTenant::class,
            'merchant.approved' => EnsureMerchantApproved::class,
            'role' => EnsureRole::class,
        ]);

        // Locale first (so validation messages are translated), then tenant
        // resolution — which must run after authentication so the global scopes
        // are armed before any query runs.
        $middleware->api(append: [
            SetLocale::class,
            ResolveTenant::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );

        /*
         * Uniform error envelope (ARCHITECTURE.md §7).
         *
         * Every API error carries a stable machine-readable `error_code`.
         * Clients switch on that, never on `message`, which is localized.
         */
        $exceptions->render(function (InvalidStatusTransition $e, Request $request) {
            if (! $request->is('api/*')) {
                return null;
            }

            return response()->json([
                'message' => __('errors.invalid_status_transition'),
                'error_code' => $e->errorCode(),
                'from' => $e->from->value,
                'to' => $e->to->value,
            ], 422);
        });

        /*
         * Lost the race for a slot (§6.3). 409 rather than 422, because nothing
         * about the request was invalid — the world simply changed underneath
         * it. The client should refresh availability and re-prompt.
         */
        $exceptions->render(function (SlotNoLongerAvailable $e, Request $request) {
            if (! $request->is('api/*')) {
                return null;
            }

            return response()->json([
                'message' => __('errors.slot_taken'),
                'error_code' => $e->errorCode(),
            ], 409);
        });

        $exceptions->render(function (ValidationException $e, Request $request) {
            if (! $request->is('api/*')) {
                return null;
            }

            return response()->json([
                'message' => $e->getMessage(),
                'error_code' => 'VALIDATION_FAILED',
                'errors' => $e->errors(),
            ], 422);
        });

        $exceptions->render(function (AuthenticationException $e, Request $request) {
            if (! $request->is('api/*')) {
                return null;
            }

            return response()->json([
                'message' => __('errors.unauthenticated'),
                'error_code' => 'UNAUTHENTICATED',
            ], 401);
        });

        /*
         * Cross-tenant access returns 404, never 403.
         *
         * A 403 would confirm the resource EXISTS, letting one merchant probe
         * another's id space. Tenant isolation has to withhold existence too
         * (ARCHITECTURE.md §4).
         */
        $exceptions->render(function (AuthorizationException $e, Request $request) {
            if (! $request->is('api/*')) {
                return null;
            }

            return response()->json([
                'message' => __('errors.not_found'),
                'error_code' => 'NOT_FOUND',
            ], 404);
        });

        $exceptions->render(function (ModelNotFoundException|NotFoundHttpException $e, Request $request) {
            if (! $request->is('api/*')) {
                return null;
            }

            return response()->json([
                'message' => __('errors.not_found'),
                'error_code' => 'NOT_FOUND',
            ], 404);
        });
    })->create();
