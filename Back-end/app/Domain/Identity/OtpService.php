<?php

namespace App\Domain\Identity;

use App\Domain\Identity\Sms\SmsSender;
use App\Models\OtpCode;
use App\Support\PhoneNumber;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Hash;
use RuntimeException;

/**
 * One-time passcodes for phone login (spec §34).
 *
 * Security properties, all of which matter:
 *   · codes are stored HASHED — a database read never reveals a live code
 *   · comparison is constant-time via Hash::check
 *   · a code is single-use (consumed_at) and time-boxed (expires_at)
 *   · attempts are counted, and the code burns after max_attempts
 *   · requesting a new code invalidates the previous one for that phone
 */
class OtpService
{
    public function __construct(private readonly SmsSender $sms) {}

    /**
     * Issue a code and send it.
     *
     * Returns the OtpCode row. The plaintext code is deliberately NOT returned
     * — nothing outside this method should ever hold it.
     */
    public function request(string $phone, string $purpose = 'login', ?string $ip = null): OtpCode
    {
        $phone = PhoneNumber::normalize($phone) ?? $phone;

        // A new request supersedes any outstanding code for this phone+purpose,
        // so an attacker cannot keep several live codes in flight.
        OtpCode::query()
            ->where('phone', $phone)
            ->where('purpose', $purpose)
            ->whereNull('consumed_at')
            ->update(['consumed_at' => CarbonImmutable::now()]);

        $code = $this->generateCode();

        $otp = OtpCode::create([
            'phone' => $phone,
            'code_hash' => Hash::make($code),
            'purpose' => $purpose,
            'ip_hash' => $ip !== null ? hash('sha256', $ip) : null,
            'expires_at' => CarbonImmutable::now()->addSeconds(config('wasla.otp.ttl_seconds')),
        ]);

        $this->sms->send($phone, __('auth.otp_message', ['code' => $code]));

        return $otp;
    }

    /**
     * Check a submitted code.
     *
     * Returns true only for a live, unconsumed, non-exhausted, matching code —
     * and consumes it on success so it cannot be replayed.
     */
    public function verify(string $phone, string $code, string $purpose = 'login'): bool
    {
        $phone = PhoneNumber::normalize($phone) ?? $phone;

        $otp = OtpCode::query()
            ->where('phone', $phone)
            ->where('purpose', $purpose)
            ->usable()
            ->latest('id')
            ->first();

        if ($otp === null) {
            return false;
        }

        if ($otp->isExhausted()) {
            // Burn it: too many guesses against this code.
            $otp->consume();

            return false;
        }

        // Count the attempt BEFORE checking, so a failed check always costs one.
        $otp->increment('attempts');

        if (! Hash::check($code, $otp->code_hash)) {
            return false;
        }

        $otp->consume();

        return true;
    }

    /**
     * The code itself.
     *
     * ====================================================================
     * DEVELOPMENT SHORTCUT (requested 2026-08-15): while no SMS provider is
     * integrated, every code is the fixed value from config so the apps can be
     * driven end to end.
     *
     * The production guard below is not optional. A fixed OTP means knowing
     * someone's phone number is enough to become them, so this refuses to run
     * in production rather than trusting that someone remembered to unset the
     * env var before launch.
     * ====================================================================
     */
    private function generateCode(): string
    {
        $fixed = config('wasla.otp.fixed_code');

        if (filled($fixed)) {
            // The fixed code is refused in production UNLESS explicitly opted in
            // (WASLA_OTP_ALLOW_FIXED_IN_PRODUCTION=true) — a deliberate, dangerous
            // switch for pre-launch testing / App Review before an SMS provider is
            // wired. A fixed OTP lets anyone who knows a phone number sign in as
            // that user, so it must be turned off before real customers use it.
            if (app()->isProduction() && ! config('wasla.otp.allow_fixed_in_production')) {
                throw new RuntimeException(
                    'WASLA_OTP_FIXED_CODE is set in production. A fixed OTP would let '
                    .'anyone sign in as any user. Unset it, or explicitly set '
                    .'WASLA_OTP_ALLOW_FIXED_IN_PRODUCTION=true for pre-launch testing.'
                );
            }

            return (string) $fixed;
        }

        $length = (int) config('wasla.otp.length', 4);
        $max = (10 ** $length) - 1;

        return str_pad((string) random_int(0, $max), $length, '0', STR_PAD_LEFT);
    }

    /**
     * Is the fixed development code active? Surfaced in the API response so the
     * apps can show a hint during testing instead of leaving people guessing.
     */
    public function isUsingFixedCode(): bool
    {
        return filled(config('wasla.otp.fixed_code'))
            && (! app()->isProduction() || (bool) config('wasla.otp.allow_fixed_in_production'));
    }
}
