<?php

namespace App\Http\Controllers\Api\V1\Auth;

use App\Http\Controllers\Controller;
use App\Http\Resources\DriverResource;
use App\Http\Resources\UserResource;
use App\Models\Driver;
use App\Support\PhoneNumber;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;

/**
 * Driver app sign-in: the phone + password the merchant set when creating the
 * driver. Same posture as the merchant login — one generic failure, timing
 * equalised, throttled per phone+IP.
 */
class DriverAuthController extends Controller
{
    /** POST /auth/driver/login */
    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'phone' => ['required', 'string', 'max:20'],
            'password' => ['required', 'string', 'max:255'],
            'device_name' => ['sometimes', 'nullable', 'string', 'max:80'],
        ]);

        $phone = PhoneNumber::normalize($data['phone']) ?? '';
        $throttleKey = 'driver-login:'.$phone.'|'.$request->ip();

        if (RateLimiter::tooManyAttempts($throttleKey, 5)) {
            return response()->json([
                'message' => __('auth.throttle', ['seconds' => RateLimiter::availableIn($throttleKey)]),
                'error_code' => 'LOGIN_THROTTLED',
                'retry_after_seconds' => RateLimiter::availableIn($throttleKey),
            ], 429);
        }

        $driver = $phone === '' ? null : Driver::withoutTenancy()->with('user')->where('phone', $phone)->first();
        $user = $driver?->user;

        $passwordMatches = $user?->password !== null && Hash::check($data['password'], $user->password);

        if (! $passwordMatches) {
            if ($user === null) {
                Hash::check($data['password'], Hash::make('timing-equaliser'));
            }
            RateLimiter::hit($throttleKey, 300);

            return response()->json(['message' => __('auth.failed'), 'error_code' => 'INVALID_CREDENTIALS'], 422);
        }

        if (! $driver->is_active || ! $user->is_active) {
            return response()->json(['message' => __('errors.account_disabled'), 'error_code' => 'ACCOUNT_DISABLED'], 403);
        }

        RateLimiter::clear($throttleKey);
        $user->forceFill(['last_login_at' => CarbonImmutable::now()])->save();

        return response()->json([
            'token' => $user->createToken(($data['device_name'] ?? null) ?: 'driver-app')->plainTextToken,
            'user' => new UserResource($user),
            'driver' => new DriverResource($driver),
            'store' => ['token' => $driver->store?->public_token, 'name' => $driver->store?->name_ar],
        ]);
    }

    /** POST /driver/logout — revoke this device's token only. */
    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()?->delete();

        return response()->json(['message' => __('auth.logged_out')]);
    }
}
