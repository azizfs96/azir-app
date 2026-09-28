<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Per-request locale (spec §33).
 *
 * Arabic is the platform default; English is opt-in. Resolution order:
 *
 *   1. the authenticated user's saved preference — an explicit choice wins
 *   2. the Accept-Language header — what the device is set to
 *   3. the configured default (ar)
 *
 * Only locales in config('wasla.supported_locales') are honoured, so a header
 * of "fr" falls back rather than half-translating the response.
 */
class SetLocale
{
    public function handle(Request $request, Closure $next): Response
    {
        $supported = config('wasla.supported_locales', ['ar', 'en']);

        $locale = $request->user()?->locale
            ?? $this->fromHeader($request, $supported)
            ?? config('app.locale');

        if (in_array($locale, $supported, true)) {
            app()->setLocale($locale);
        }

        return $next($request);
    }

    /**
     * @param  array<int, string>  $supported
     */
    private function fromHeader(Request $request, array $supported): ?string
    {
        $header = $request->header('Accept-Language');

        if ($header === null) {
            return null;
        }

        // "en-US,en;q=0.9,ar;q=0.8" -> first supported primary subtag.
        foreach (explode(',', $header) as $part) {
            $tag = strtolower(trim(explode(';', $part)[0]));
            $primary = explode('-', $tag)[0];

            if (in_array($primary, $supported, true)) {
                return $primary;
            }
        }

        return null;
    }
}
