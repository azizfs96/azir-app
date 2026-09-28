<?php

namespace App\Http\Controllers\Api\V1\Auth;

use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\MerchantLoginRequest;
use App\Http\Resources\UserResource;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;

/**
 * Merchant and admin authentication: email + password (spec §34).
 */
class MerchantAuthController extends Controller
{
    /**
     * POST /auth/login
     */
    public function login(MerchantLoginRequest $request): JsonResponse
    {
        $email = strtolower((string) $request->input('email'));
        $throttleKey = 'login:'.$email.'|'.$request->ip();

        if (RateLimiter::tooManyAttempts($throttleKey, 5)) {
            return response()->json([
                'message' => __('auth.throttle', ['seconds' => RateLimiter::availableIn($throttleKey)]),
                'error_code' => 'LOGIN_THROTTLED',
                'retry_after_seconds' => RateLimiter::availableIn($throttleKey),
            ], 429);
        }

        $user = User::where('email', $email)->first();

        /*
         * One generic failure for "no such user" and "wrong password".
         *
         * Distinguishing them would let anyone enumerate which emails have
         * merchant accounts. Hash::check runs on a dummy hash when the user is
         * missing so the timing does not give it away either.
         */
        $passwordMatches = $user?->password !== null
            && Hash::check((string) $request->input('password'), $user->password);

        if (! $passwordMatches) {
            if ($user === null) {
                Hash::check((string) $request->input('password'), Hash::make('timing-equaliser'));
            }

            RateLimiter::hit($throttleKey, 300);

            return response()->json([
                'message' => __('auth.failed'),
                'error_code' => 'INVALID_CREDENTIALS',
            ], 422);
        }

        // Customers must not be able to sign in through the merchant endpoint.
        if ($user->isCustomer()) {
            RateLimiter::hit($throttleKey, 300);

            return response()->json([
                'message' => __('auth.failed'),
                'error_code' => 'INVALID_CREDENTIALS',
            ], 422);
        }

        if (! $user->is_active) {
            return response()->json([
                'message' => __('errors.account_disabled'),
                'error_code' => 'ACCOUNT_DISABLED',
            ], 403);
        }

        RateLimiter::clear($throttleKey);

        $user->forceFill(['last_login_at' => CarbonImmutable::now()])->save();

        return response()->json([
            'token' => $user->createToken($request->input('device_name') ?: 'merchant-dashboard')->plainTextToken,
            'user' => new UserResource($user->load('merchant')),
        ]);
    }

    /**
     * POST /auth/logout — revokes only the token that made this request, so
     * signing out on a phone does not sign the merchant out on their tablet.
     */
    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => __('auth.logged_out')]);
    }

    /**
     * PATCH /auth/me/locale
     *
     * An explicit in-app language choice IS the user's preference, so it is
     * persisted rather than left to the Accept-Language header. SetLocale gives
     * the stored preference precedence over the header, which means without
     * this the dashboard's language toggle would change the interface chrome
     * but not the data the API returns — service names would stay Arabic in an
     * otherwise English dashboard.
     */
    public function updateLocale(Request $request): JsonResponse
    {
        $data = $request->validate([
            'locale' => ['required', 'in:ar,en'],
        ]);

        $request->user()->forceFill(['locale' => $data['locale']])->save();

        return response()->json(['locale' => $data['locale']]);
    }

    /**
     * GET /auth/me
     */
    public function me(Request $request): UserResource
    {
        $user = $request->user();

        return new UserResource(
            $user->isCustomer() ? $user->load('customer') : $user->load('merchant')
        );
    }
}
