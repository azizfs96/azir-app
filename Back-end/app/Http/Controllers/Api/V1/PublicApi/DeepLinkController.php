<?php

namespace App\Http\Controllers\Api\V1\PublicApi;

use App\Http\Controllers\Controller;
use App\Models\DeepLinkAttribution;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * ============================================================================
 * DEFERRED DEEP LINKING (spec §7)
 *
 *   "If Wasla is NOT installed: QR -> landing page -> App Store -> install ->
 *    open Wasla -> automatically open the original merchant.
 *    Do not lose the original merchant context after installation.
 *    This is extremely important."
 *
 * Firebase Dynamic Links shut down in August 2025, so this is in-house
 * (ARCHITECTURE.md §8.3):
 *
 *   1. POST /deep-link/record   — landing page stores a device fingerprint
 *   2. (user installs the app)
 *   3. POST /deep-link/claim    — app sends its own fingerprint, gets the token
 *
 * Android does better than this via Play Install Referrer (exact, not
 * probabilistic). iOS relies on the fingerprint match, with the visible
 * "enter store code" fallback so a miss is never a dead end.
 * ============================================================================
 */
class DeepLinkController extends Controller
{
    /**
     * POST /deep-link/record — called by the web landing page before it
     * redirects to the App Store.
     */
    public function record(Request $request): JsonResponse
    {
        $data = $request->validate([
            'token' => ['required', 'string', 'max:20'],
            'platform' => ['sometimes', 'nullable', 'in:ios,android,web'],
            'screen' => ['sometimes', 'nullable', 'string', 'max:40'],
        ]);

        DeepLinkAttribution::create([
            'store_public_token' => strtoupper($data['token']),
            'fingerprint_hash' => $this->fingerprint($request, $data['screen'] ?? null),
            'platform' => $data['platform'] ?? null,
            'ip_hash' => $this->hashIp($request),
            'user_agent' => substr((string) $request->userAgent(), 0, 512),
            'expires_at' => CarbonImmutable::now()
                ->addMinutes((int) config('wasla.attribution_ttl_minutes', 60)),
        ]);

        return response()->json(['recorded' => true], 201);
    }

    /**
     * POST /deep-link/claim — called on first app launch.
     *
     * Returns the store token if this device recently opened a Wasla link, so
     * the app can jump straight to that merchant.
     */
    public function claim(Request $request): JsonResponse
    {
        $data = $request->validate([
            'platform' => ['sometimes', 'nullable', 'in:ios,android,web'],
            'screen' => ['sometimes', 'nullable', 'string', 'max:40'],
            // Android supplies this from the Play Install Referrer, which is
            // exact — no fingerprint guessing needed.
            'install_referrer' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);

        // Exact path first.
        if (filled($data['install_referrer'] ?? null)) {
            $token = $this->tokenFromReferrer($data['install_referrer']);

            if ($token !== null) {
                return response()->json(['token' => $token, 'matched_by' => 'install_referrer']);
            }
        }

        // Probabilistic fallback.
        $attribution = DeepLinkAttribution::query()
            ->claimable()
            ->where('fingerprint_hash', $this->fingerprint($request, $data['screen'] ?? null))
            ->latest('id')
            ->first();

        if ($attribution === null) {
            // Not an error: most launches are simply not deferred-link installs.
            // The app falls back to its normal home screen.
            return response()->json(['token' => null, 'matched_by' => null]);
        }

        $attribution->forceFill([
            'claimed_by_customer_id' => $request->user()?->customer?->id,
            'claimed_at' => CarbonImmutable::now(),
        ])->save();

        return response()->json([
            'token' => $attribution->store_public_token,
            'matched_by' => 'fingerprint',
        ]);
    }

    /**
     * A coarse device fingerprint.
     *
     * Deliberately coarse — IP + platform + screen + language. It is enough to
     * match one device across a few minutes, and not enough to track anybody.
     * Rows expire after an hour and are hashed, never stored raw.
     */
    private function fingerprint(Request $request, ?string $screen): string
    {
        return hash('sha256', implode('|', [
            $this->hashIp($request),
            $this->platformOf($request),
            $screen ?? '',
            substr((string) $request->header('Accept-Language'), 0, 10),
        ]));
    }

    private function hashIp(Request $request): string
    {
        return hash('sha256', (string) $request->ip());
    }

    private function platformOf(Request $request): string
    {
        $agent = strtolower((string) $request->userAgent());

        return match (true) {
            str_contains($agent, 'iphone'), str_contains($agent, 'ipad') => 'ios',
            str_contains($agent, 'android') => 'android',
            default => 'web',
        };
    }

    /**
     * Play Install Referrer arrives as a query string, e.g. "utm_source=wasla&store=8F72K".
     */
    private function tokenFromReferrer(string $referrer): ?string
    {
        parse_str($referrer, $parts);

        $token = $parts['store'] ?? null;

        return is_string($token) && $token !== '' ? strtoupper($token) : null;
    }
}
