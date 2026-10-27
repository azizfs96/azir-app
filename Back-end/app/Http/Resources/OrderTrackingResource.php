<?php

namespace App\Http\Resources;

use App\Domain\Ordering\DeliveryPricing;
use App\Domain\Ordering\OrderStatus;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Live delivery tracking — polled by the customer's tracking screen and the
 * merchant's order card while an order is out for delivery. Small on purpose:
 * the driver's last position, the two endpoints of the trip, and an ETA.
 *
 * @mixin \App\Models\Order
 */
class OrderTrackingResource extends JsonResource
{
    /** Assumed urban delivery speed for the ETA (km/h) + handover minutes. */
    private const ETA_SPEED_KMH = 28.0;

    private const ETA_HANDOVER_MIN = 2.0;

    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        $driver = $this->driver;
        $moving = $this->status === OrderStatus::OutForDelivery;
        $location = null;
        $eta = null;

        if ($moving && $driver !== null && $driver->last_latitude !== null && $driver->last_located_at !== null) {
            $location = [
                'latitude' => (float) $driver->last_latitude,
                'longitude' => (float) $driver->last_longitude,
                'heading' => $driver->last_heading,
                'speed_kmh' => $driver->last_speed_kmh !== null ? (float) $driver->last_speed_kmh : null,
                'located_at' => $driver->last_located_at->toIso8601String(),
                'fresh' => $driver->hasFreshLocation(),
            ];

            if ($this->delivery_latitude !== null && $this->delivery_longitude !== null) {
                $km = DeliveryPricing::haversineKm(
                    (float) $driver->last_latitude, (float) $driver->last_longitude,
                    (float) $this->delivery_latitude, (float) $this->delivery_longitude,
                ) * 1.3;
                $eta = (int) ceil($km / self::ETA_SPEED_KMH * 60 + self::ETA_HANDOVER_MIN);
            }
        }

        $branch = $this->branch;

        return [
            'order_id' => $this->id,
            'status' => $this->status->value,
            'driver' => $driver === null ? null : [
                'id' => $driver->id,
                'name' => $driver->name,
                'phone' => $driver->phone,
                'vehicle' => $driver->vehicle,
            ],
            'driver_location' => $location,
            'eta_minutes' => $eta,
            'origin' => $branch === null ? null : [
                'name' => $branch->displayName(app()->getLocale()),
                'latitude' => $branch->latitude !== null ? (float) $branch->latitude : null,
                'longitude' => $branch->longitude !== null ? (float) $branch->longitude : null,
            ],
            'destination' => [
                'address' => $this->delivery_address,
                'latitude' => $this->delivery_latitude !== null ? (float) $this->delivery_latitude : null,
                'longitude' => $this->delivery_longitude !== null ? (float) $this->delivery_longitude : null,
            ],
            'distance_km' => $this->delivery_distance_km !== null ? (float) $this->delivery_distance_km : null,
            'assigned_at' => $this->assigned_at?->toIso8601String(),
            'out_for_delivery_at' => $this->out_for_delivery_at?->toIso8601String(),
            'completed_at' => $this->completed_at?->toIso8601String(),
        ];
    }
}
