<?php

namespace App\Support;

use Illuminate\Database\Eloquent\Model;
use Random\RandomException;
use RuntimeException;

/**
 * Public identifiers that never expose internal database ids (spec §24).
 *
 * ARCHITECTURE.md §8.2 — the alphabet is Crockford-style base32 with the
 * visually ambiguous characters removed:
 *
 *      I / 1 / l   look alike
 *      O / 0       look alike
 *      U           removed (Crockford convention; avoids accidental profanity)
 *
 * That matters because these codes get PRINTED on a salon's window and read
 * aloud over the phone. 30 symbols ^ 8 characters is ~6.6 x 10^11 combinations
 * — not enumerable at the public rate limit of 60 req/min (§7.6).
 *
 * Generated with random_int (CSPRNG), never derived from the row id, and never
 * sequential.
 */
class TokenGenerator
{
    public const ALPHABET = '23456789ABCDEFGHJKMNPQRSTVWXYZ';

    public const STORE_TOKEN_LENGTH = 8;

    /**
     * A store's public token — the "8F72K" in wasla.sa/s/8F72K.
     *
     * @param  class-string<Model>  $model  Model to check uniqueness against.
     */
    public static function uniqueStoreToken(string $model, string $column = 'public_token'): string
    {
        // 10 attempts against ~8.5e11 keyspace: collision-retry exhaustion here
        // would mean something is badly wrong, so fail loudly rather than loop.
        for ($attempt = 0; $attempt < 10; $attempt++) {
            $token = self::random(self::STORE_TOKEN_LENGTH);

            $exists = $model::query()
                ->withoutGlobalScopes()
                ->where($column, $token)
                ->exists();

            if (! $exists) {
                return $token;
            }
        }

        throw new RuntimeException('Unable to generate a unique store token after 10 attempts.');
    }

    /**
     * Human-readable booking reference, e.g. WSL-4K7QX2.
     * Spoken over the phone, so it uses the same unambiguous alphabet.
     */
    public static function uniqueBookingReference(string $model, string $column = 'reference'): string
    {
        for ($attempt = 0; $attempt < 10; $attempt++) {
            $reference = 'WSL-'.self::random(6);

            $exists = $model::query()
                ->withoutGlobalScopes()
                ->where($column, $reference)
                ->exists();

            if (! $exists) {
                return $reference;
            }
        }

        throw new RuntimeException('Unable to generate a unique booking reference after 10 attempts.');
    }

    /**
     * @throws RandomException
     */
    public static function random(int $length): string
    {
        $alphabetLength = strlen(self::ALPHABET) - 1;
        $token = '';

        for ($i = 0; $i < $length; $i++) {
            $token .= self::ALPHABET[random_int(0, $alphabetLength)];
        }

        return $token;
    }

    /**
     * Normalise user-typed input — the "enter store code" fallback when iOS
     * deferred deep linking misses (ARCHITECTURE.md §8.3).
     *
     * The alphabet contains none of 0 1 I L O U, so those characters can never
     * legitimately appear in a token. When someone types one they have misread
     * a lookalike, so fold it onto the character that IS in the alphabet:
     *
     *      0 and O  ->  D     (a printed D misread as O/0)
     *      1, I, L  ->  J     (a printed J misread as I/1/L)
     *      U        ->  V
     *
     * Everything outside the alphabet (spaces, dashes, the "wasla.sa/s/" a user
     * may paste in front) is stripped rather than silently mangled.
     */
    public static function normalize(string $input): string
    {
        $upper = strtoupper(trim($input));

        // Drop a pasted URL prefix, keeping only what follows the last slash.
        if (str_contains($upper, '/')) {
            $upper = substr($upper, strrpos($upper, '/') + 1);
        }

        $folded = strtr($upper, [
            '0' => 'D', 'O' => 'D',
            '1' => 'J', 'I' => 'J', 'L' => 'J',
            'U' => 'V',
        ]);

        // Keep only real alphabet characters.
        $clean = '';
        foreach (str_split($folded) as $character) {
            if (str_contains(self::ALPHABET, $character)) {
                $clean .= $character;
            }
        }

        return $clean;
    }
}
