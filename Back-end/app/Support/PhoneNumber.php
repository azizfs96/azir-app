<?php

namespace App\Support;

/**
 * Saudi phone normalisation.
 *
 * Customers type their number every way imaginable — 0501234567, 501234567,
 * +966 50 123 4567, 00966501234567. All of those are ONE person, and if they
 * are not normalised the same human ends up with several accounts and loses
 * their booking history.
 *
 * Canonical form is E.164: +9665XXXXXXXX
 */
class PhoneNumber
{
    private const SAUDI_CODE = '966';

    /**
     * Normalise to E.164, or null if it cannot be a valid Saudi mobile.
     */
    public static function normalize(string $input): ?string
    {
        // Keep digits only; a leading + is re-added from the country code below.
        $digits = preg_replace('/\D+/', '', $input) ?? '';

        if ($digits === '') {
            return null;
        }

        // 00966... international prefix
        if (str_starts_with($digits, '00'.self::SAUDI_CODE)) {
            $digits = substr($digits, 2);
        }

        // 966...
        if (str_starts_with($digits, self::SAUDI_CODE)) {
            $national = substr($digits, strlen(self::SAUDI_CODE));
        } elseif (str_starts_with($digits, '0')) {
            // 0501234567 -> 501234567
            $national = substr($digits, 1);
        } else {
            $national = $digits;
        }

        // Saudi mobiles are 9 digits and always start with 5.
        if (strlen($national) !== 9 || ! str_starts_with($national, '5')) {
            return null;
        }

        return '+'.self::SAUDI_CODE.$national;
    }

    public static function isValid(string $input): bool
    {
        return self::normalize($input) !== null;
    }

    /**
     * Masked form for display and logs: +9665****4567
     */
    public static function mask(string $e164): string
    {
        if (strlen($e164) < 8) {
            return $e164;
        }

        return substr($e164, 0, 5).'****'.substr($e164, -4);
    }
}
