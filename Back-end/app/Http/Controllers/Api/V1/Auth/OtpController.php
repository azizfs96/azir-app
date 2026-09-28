<?php

namespace App\Http\Controllers\Api\V1\Auth;

use App\Domain\Identity\OtpService;
use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\OtpRequestRequest;
use App\Http\Requests\Auth\OtpVerifyRequest;
use App\Http\Resources\UserResource;
use App\Models\Customer;
use App\Models\DeviceToken;
use App\Models\User;
use App\Support\PhoneNumber;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\RateLimiter;

/**
 * Customer authentication: phone + OTP (spec §34).
 *
 * There is no password anywhere in this flow. A customer's identity is their
 * phone number, which is also what powers reminders and no-show tracking.
 */
class OtpController extends Controller
{
    public function __construct(private readonly OtpService $otp) {}

    /**
     * POST /auth/otp/request
     *
     * Rate limited per §7.6: 3 per 5 minutes per phone, 10 per hour per IP.
     * Both limits matter — the per-phone limit stops SMS-bombing one victim,
     * the per-IP limit stops enumerating many numbers.
     */
    public function request(OtpRequestRequest $request): JsonResponse
    {
        $phone = $request->normalizedPhone();

        $phoneKey = 'otp-request:phone:'.$phone;
        $ipKey = 'otp-request:ip:'.$request->ip();

        if (RateLimiter::tooManyAttempts($phoneKey, 3) || RateLimiter::tooManyAttempts($ipKey, 10)) {
            return response()->json([
                'message' => __('errors.otp_throttled'),
                'error_code' => 'OTP_THROTTLED',
                'retry_after_seconds' => RateLimiter::availableIn($phoneKey),
            ], 429);
        }

        RateLimiter::hit($phoneKey, 300);
        RateLimiter::hit($ipKey, 3600);

        $this->otp->request($phone, 'login', $request->ip());

        return response()->json([
            'message' => __('auth.otp_sent'),
            'phone' => PhoneNumber::mask($phone),
            'expires_in_seconds' => (int) config('wasla.otp.ttl_seconds'),

            // Development aid only — tells the app to show the fixed-code hint.
            // Always false once a real SMS provider is wired up.
            'development_mode' => $this->otp->isUsingFixedCode(),
        ]);
    }

    /**
     * POST /auth/otp/verify
     *
     * On success the customer is created if they do not exist yet — there is no
     * separate "register" step, because asking someone to register before they
     * have seen any value is a drop-off (spec §41).
     */
    public function verify(OtpVerifyRequest $request): JsonResponse
    {
        $phone = $request->normalizedPhone();
        $throttleKey = 'otp-verify:'.$phone;

        if (RateLimiter::tooManyAttempts($throttleKey, 5)) {
            return response()->json([
                'message' => __('errors.otp_throttled'),
                'error_code' => 'OTP_THROTTLED',
                'retry_after_seconds' => RateLimiter::availableIn($throttleKey),
            ], 429);
        }

        RateLimiter::hit($throttleKey, 300);

        if (! $this->otp->verify($phone, (string) $request->input('code'))) {
            return response()->json([
                'message' => __('errors.otp_invalid'),
                'error_code' => 'OTP_INVALID',
            ], 422);
        }

        RateLimiter::clear($throttleKey);

        $user = DB::transaction(fn () => $this->resolveCustomer($phone, $request->validated()));

        if (! $user->is_active) {
            return response()->json([
                'message' => __('errors.account_disabled'),
                'error_code' => 'ACCOUNT_DISABLED',
            ], 403);
        }

        $this->rememberDevice($user, $request->validated());

        $user->forceFill(['last_login_at' => CarbonImmutable::now()])->save();

        return response()->json([
            'token' => $user->createToken('customer-app')->plainTextToken,
            'user' => new UserResource($user->load('customer')),
        ]);
    }

    /**
     * Find the customer behind this phone, or create them.
     *
     * @param  array<string, mixed>  $data
     */
    private function resolveCustomer(string $phone, array $data): User
    {
        $user = User::where('phone', $phone)->first();

        if ($user === null) {
            $name = trim(($data['first_name'] ?? '').' '.($data['last_name'] ?? ''));

            $user = User::create([
                'name' => $name !== '' ? $name : __('auth.default_customer_name'),
                'phone' => $phone,
                'role' => User::ROLE_CUSTOMER,
            ]);
        }

        // Verifying the code IS verifying the phone.
        $user->forceFill(['phone_verified_at' => CarbonImmutable::now()])->save();

        if ($user->isCustomer() && $user->customer === null) {
            Customer::create([
                'user_id' => $user->id,
                'first_name' => $data['first_name'] ?? null,
                'last_name' => $data['last_name'] ?? null,
            ]);

            $user->load('customer');
        }

        return $user;
    }

    /** @param  array<string, mixed>  $data */
    private function rememberDevice(User $user, array $data): void
    {
        if (empty($data['device_token']) || empty($data['platform'])) {
            return;
        }

        DeviceToken::updateOrCreate(
            ['user_id' => $user->id, 'token' => $data['device_token']],
            ['platform' => $data['platform'], 'last_seen_at' => CarbonImmutable::now()],
        );
    }
}
