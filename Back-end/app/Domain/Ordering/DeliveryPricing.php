<?php

namespace App\Domain\Ordering;

use App\Models\BookingSettings;
use App\Models\Branch;

/**
 * The answer to "how much is delivery to here?" — one object the quote
 * endpoint, the cart preview and order placement all share, so what the
 * customer sees before ordering is exactly what the server charges.
 */
final class DeliveryQuote
{
    public const REASON_OUT_OF_RANGE = 'OUT_OF_RANGE';

    /** The merchant priced by distance but a pin is missing; the flat fee applied. */
    public const REASON_NO_COORDINATES = 'NO_COORDINATES';

    public function __construct(
        public readonly bool $allowed,
        public readonly ?string $reason,
        public readonly ?float $distanceKm,
        public readonly float $fee,
        public readonly string $mode,
        public readonly ?float $maxDistanceKm,
    ) {}

    /** @return array<string, mixed> */
    public function toArray(): array
    {
        return [
            'allowed' => $this->allowed,
            'reason' => $this->reason,
            'distance_km' => $this->distanceKm,
            'fee' => $this->fee,
            'mode' => $this->mode,
            'max_distance_km' => $this->maxDistanceKm,
        ];
    }
}

/**
 * Distance-based delivery pricing (merchant-configured, server-computed).
 *
 * Distance = great-circle distance between the branch and the customer's pin
 * × the store's road factor (1.3 by default — a good approximation of road
 * distance in a grid city without a paid routing API; the factor is a setting
 * so it can be tuned, and this class is the single place to swap in a real
 * routing provider later).
 */
final class DeliveryPricing
{
    public const MODE_FIXED = 'fixed';

    public const MODE_PER_KM = 'per_km';

    public const MODE_TIERS = 'tiers';

    public const MODES = [self::MODE_FIXED, self::MODE_PER_KM, self::MODE_TIERS];

    private const EARTH_RADIUS_KM = 6371.0088;

    public static function haversineKm(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        return 2 * self::EARTH_RADIUS_KM * asin(min(1.0, sqrt($a)));
    }

    /**
     * Straight-line × road factor, to 0.1 km; null when either pin is missing.
     */
    public static function distanceKm(?BookingSettings $settings, ?Branch $branch, ?float $lat, ?float $lng): ?float
    {
        if ($branch?->latitude === null || $branch?->longitude === null || $lat === null || $lng === null) {
            return null;
        }

        $factor = max(1.0, (float) ($settings?->delivery_road_factor ?? 1.3));

        return round(self::haversineKm((float) $branch->latitude, (float) $branch->longitude, $lat, $lng) * $factor, 1);
    }

    public function quote(?BookingSettings $settings, ?Branch $branch, ?float $lat, ?float $lng): DeliveryQuote
    {
        $mode = (string) ($settings?->delivery_pricing_mode ?: self::MODE_FIXED);
        if (! in_array($mode, self::MODES, true)) {
            $mode = self::MODE_FIXED;
        }

        $fixed = round((float) ($settings?->delivery_fee ?? 0), 2);
        $distance = self::distanceKm($settings, $branch, $lat, $lng);

        // A configured radius applies to every mode; 0/null = unlimited.
        $max = (float) ($settings?->delivery_max_distance_km ?? 0);
        $max = $max > 0 ? $max : null;

        if ($max !== null && $distance !== null && $distance > $max) {
            return new DeliveryQuote(false, DeliveryQuote::REASON_OUT_OF_RANGE, $distance, 0.0, $mode, $max);
        }

        if ($mode === self::MODE_FIXED) {
            return new DeliveryQuote(true, null, $distance, $fixed, $mode, $max);
        }

        // Distance pricing without a pin on either side cannot be computed:
        // fall back to the flat fee rather than refuse the order.
        if ($distance === null) {
            return new DeliveryQuote(true, DeliveryQuote::REASON_NO_COORDINATES, null, $fixed, $mode, $max);
        }

        if ($mode === self::MODE_PER_KM) {
            $fee = (float) ($settings->delivery_base_fee ?? 0) + (float) ($settings->delivery_fee_per_km ?? 0) * $distance;

            return new DeliveryQuote(true, null, $distance, round($fee, 2), $mode, $max);
        }

        // Tiers: [{up_to_km, fee}, …] — the first tier the distance fits in.
        $tiers = collect((array) ($settings->delivery_tiers ?? []))
            ->filter(fn ($t) => is_array($t) && isset($t['up_to_km'], $t['fee']))
            ->sortBy(fn ($t) => (float) $t['up_to_km'])
            ->values();

        foreach ($tiers as $tier) {
            if ($distance <= (float) $tier['up_to_km']) {
                return new DeliveryQuote(true, null, $distance, round((float) $tier['fee'], 2), $mode, $max);
            }
        }

        // Beyond the last tier: the merchant never priced this far.
        return $tiers->isEmpty()
            ? new DeliveryQuote(true, DeliveryQuote::REASON_NO_COORDINATES, $distance, $fixed, $mode, $max)
            : new DeliveryQuote(false, DeliveryQuote::REASON_OUT_OF_RANGE, $distance, 0.0, $mode, $max);
    }
}
