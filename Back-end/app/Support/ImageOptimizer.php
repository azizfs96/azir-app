<?php

namespace App\Support;

/**
 * ============================================================================
 * SHRINK UPLOADS AT THE DOOR
 *
 * Merchants upload straight off a phone camera: 4000×3000, five megabytes.
 * Stored as-is, every customer then downloads and DECODES that on a phone —
 * the storefront-open freeze traced back to exactly this. A cover never
 * renders wider than ~1300 physical pixels, so anything bigger is waste.
 *
 * GD only — no new dependency — and ENCODER-ADAPTIVE: a build without JPEG
 * support (this project's static dev PHP has exactly that) falls back to the
 * next available format, and the caller receives the TRUE extension of what
 * was stored. Anything undecodable passes through untouched: a heavy image
 * beats a failed upload every time.
 * ============================================================================
 */
final class ImageOptimizer
{
    /**
     * Downscale so the longest side is at most $maxDimension.
     *
     * @return array{0: string, 1: string} [bytes, extension] — the original
     *                                     bytes and mime-derived extension when
     *                                     no processing was possible or needed.
     */
    public static function shrink(string $binary, int $maxDimension, string $mime): array
    {
        $original = [$binary, self::extensionFor($mime)];

        if (! extension_loaded('gd')) {
            return $original;
        }

        try {
            $source = @imagecreatefromstring($binary);

            if ($source === false) {
                return $original;
            }

            $width = imagesx($source);
            $height = imagesy($source);
            $longest = max($width, $height);

            if ($longest <= $maxDimension) {
                imagedestroy($source);

                return $original;
            }

            $encoder = self::pickEncoder($mime);

            if ($encoder === null) {
                imagedestroy($source);

                return $original;
            }

            $scale = $maxDimension / $longest;
            $newWidth = max(1, (int) round($width * $scale));
            $newHeight = max(1, (int) round($height * $scale));

            $resized = imagecreatetruecolor($newWidth, $newHeight);

            // Keep PNG/WebP transparency (logos on coloured storefronts).
            imagealphablending($resized, false);
            imagesavealpha($resized, true);

            imagecopyresampled(
                $resized, $source,
                0, 0, 0, 0,
                $newWidth, $newHeight, $width, $height,
            );

            imagedestroy($source);

            ob_start();

            $encoded = match ($encoder) {
                'png' => imagepng($resized, null, 8),
                'webp' => imagewebp($resized, null, 82),
                'jpeg' => imagejpeg($resized, null, 82),
            };

            $output = ob_get_clean();
            imagedestroy($resized);

            if (! $encoded || $output === false || $output === '') {
                return $original;
            }

            return [$output, $encoder === 'jpeg' ? 'jpg' : $encoder];
        } catch (\Throwable) {
            return $original;
        }
    }

    /**
     * The best encoder this PHP build actually has, preferring the source
     * format so quality is not laundered through repeated conversions.
     */
    private static function pickEncoder(string $mime): ?string
    {
        $preference = match ($mime) {
            'image/png' => ['png', 'webp', 'jpeg'],
            'image/webp' => ['webp', 'png', 'jpeg'],
            default => ['jpeg', 'webp', 'png'],
        };

        foreach ($preference as $encoder) {
            if (function_exists('image'.$encoder)) {
                return $encoder;
            }
        }

        return null;
    }

    private static function extensionFor(string $mime): string
    {
        return match ($mime) {
            'image/png' => 'png',
            'image/webp' => 'webp',
            default => 'jpg',
        };
    }
}
