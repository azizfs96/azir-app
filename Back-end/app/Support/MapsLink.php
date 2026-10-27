<?php

namespace App\Support;

use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Http;

/**
 * Coordinates out of a Google Maps link a merchant pasted.
 *
 * The dashboard already extracts them client-side for long links. Merchants
 * on a phone paste SHORT links (maps.app.goo.gl/…, goo.gl/maps/…) which carry
 * no coordinates until the redirect is followed — the browser cannot do that
 * cross-origin, so the server does it here on save (and in the backfill
 * command). Without a pin a branch has no distance and no distance pricing.
 */
final class MapsLink
{
    private const PATTERNS = [
        '/@(-?\d{1,3}\.\d+),\s*(-?\d{1,3}\.\d+)/',                 // …/@lat,lng,17z
        '/[?&](?:q|ll|center|daddr|destination)=(-?\d{1,3}\.\d+)(?:,|%2C)\s*(-?\d{1,3}\.\d+)/', // ?q=lat,lng
        '/!3d(-?\d{1,3}\.\d+)!4d(-?\d{1,3}\.\d+)/',                 // …/data=!3dlat!4dlng (place links)
        '/^geo:(-?\d{1,3}\.\d+),\s*(-?\d{1,3}\.\d+)/',              // geo:lat,lng
        '/^\s*(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)\s*$/',        // bare "lat, lng"
    ];

    private const SHORT_HOSTS = ['maps.app.goo.gl', 'goo.gl', 'g.co', 'maps.google.com', 'google.com', 'www.google.com'];

    /** @return array{0: float, 1: float}|null */
    public static function parse(?string $input): ?array
    {
        if ($input === null || trim($input) === '') {
            return null;
        }

        foreach (self::PATTERNS as $pattern) {
            if (preg_match($pattern, trim($input), $m) !== 1) {
                continue;
            }
            $lat = (float) $m[1];
            $lng = (float) $m[2];
            if (abs($lat) <= 90 && abs($lng) <= 180 && ($lat !== 0.0 || $lng !== 0.0)) {
                return [$lat, $lng];
            }
        }

        return null;
    }

    /**
     * Parse, and when the link itself carries nothing, follow its redirects
     * (short links expand to a full /maps/place/…/@lat,lng URL) and look in
     * both the final URL and the page body. Network failures yield null —
     * the branch still saves, just without a pin.
     *
     * @return array{0: float, 1: float}|null
     */
    public static function resolve(?string $url): ?array
    {
        $parsed = self::parse($url);
        if ($parsed !== null || $url === null) {
            return $parsed;
        }

        $host = strtolower((string) parse_url($url, PHP_URL_HOST));
        if (! in_array($host, self::SHORT_HOSTS, true) && ! str_ends_with($host, '.google.com')) {
            return null;
        }

        try {
            $response = Http::timeout(6)
                ->withHeaders(['User-Agent' => 'Mozilla/5.0 (compatible; Azir/1.0)'])
                ->withOptions(['allow_redirects' => ['max' => 5, 'track_redirects' => true]])
                ->get($url);
        } catch (ConnectionException) {
            return null;
        }

        // The final URL after redirects: Guzzle records every hop as one header
        // value each (URLs themselves contain commas, so never split on them).
        $history = $response->toPsrResponse()->getHeader('X-Guzzle-Redirect-History');
        $finalUrl = $history === [] ? (string) ($response->effectiveUri() ?? '') : end($history);
        if ($finalUrl !== '' && ($hit = self::parse(urldecode($finalUrl))) !== null) {
            return $hit;
        }

        // Place pages embed the pin as !3d<lat>!4d<lng> or /@lat,lng in the HTML.
        $body = $response->body();
        if ($body !== '' && ($hit = self::parse(mb_substr($body, 0, 200000))) !== null) {
            return $hit;
        }

        return null;
    }
}
