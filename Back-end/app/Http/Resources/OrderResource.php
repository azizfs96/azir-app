<?php

namespace App\Http\Resources;

use App\Models\Order;
use App\Support\ZatcaQr;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * An order as both the customer app and the merchant dashboard consume it.
 *
 * @property Order $resource
 */
class OrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'reference' => $this->reference,
            'status' => $this->status->value,
            'fulfillment_type' => $this->fulfillment_type,
            'table_number' => $this->table_number,
            'party_size' => $this->party_size,
            'subtotal' => (float) $this->subtotal,
            'delivery_fee' => (float) $this->delivery_fee,
            'tax_rate' => (float) $this->tax_rate,
            'tax_amount' => (float) $this->tax_amount,
            'total' => (float) $this->total,
            // The ZATCA simplified tax invoice — present only when the order was
            // taxed. `qr` is the Base64 TLV the app/dashboard render as a QR.
            'invoice' => $this->when((float) $this->tax_amount > 0, fn () => [
                'number' => $this->reference,
                'seller_name' => $this->seller_name,
                'tax_number' => $this->tax_number,
                'commercial_registration' => $this->commercial_registration,
                'national_address' => $this->national_address,
                // The merchant's own brand logo (full URL), shown on the invoice.
                'logo' => $this->whenLoaded('store', fn () => $this->store?->logo_path
                    ? \Illuminate\Support\Facades\Storage::disk('public')->url($this->store->logo_path)
                    : null),
                'tax_rate' => (float) $this->tax_rate,
                'issued_at' => $this->created_at?->toIso8601String(),
                'qr' => ZatcaQr::forOrder($this->resource),
            ]),
            // Present only on delivery orders; the snapshot, not the live address.
            'delivery' => $this->when($this->fulfillment_type === 'delivery', fn () => [
                'address' => $this->delivery_address,
                'details' => $this->delivery_details,
                'latitude' => $this->delivery_latitude !== null ? (float) $this->delivery_latitude : null,
                'longitude' => $this->delivery_longitude !== null ? (float) $this->delivery_longitude : null,
                'distance_km' => $this->delivery_distance_km !== null ? (float) $this->delivery_distance_km : null,
            ]),
            // The driver carrying a delivery order (null until assigned).
            'driver' => $this->whenLoaded('driver', fn () => $this->driver === null ? null : [
                'id' => $this->driver->id,
                'name' => $this->driver->name,
                'phone' => $this->driver->phone,
                'vehicle' => $this->driver->vehicle,
            ]),
            'prep_minutes' => $this->prep_minutes,
            'customer_notes' => $this->customer_notes,
            'rejection_reason' => $this->rejection_reason,
            'created_at' => $this->created_at?->toIso8601String(),
            'accepted_at' => $this->accepted_at?->toIso8601String(),
            'ready_at' => $this->ready_at?->toIso8601String(),
            'assigned_at' => $this->assigned_at?->toIso8601String(),
            'out_for_delivery_at' => $this->out_for_delivery_at?->toIso8601String(),
            'completed_at' => $this->completed_at?->toIso8601String(),
            // The pickup point (loaded for the driver app and tracking).
            'branch' => $this->whenLoaded('branch', fn () => $this->branch === null ? null : [
                'id' => $this->branch->id,
                'name' => $this->branch->displayName(app()->getLocale()),
                'address' => $this->branch->address_line,
                'latitude' => $this->branch->latitude !== null ? (float) $this->branch->latitude : null,
                'longitude' => $this->branch->longitude !== null ? (float) $this->branch->longitude : null,
            ]),
            'store' => $this->whenLoaded('store', fn () => [
                'token' => $this->store->public_token,
                'name' => $this->store->name_ar,
            ]),
            'customer' => $this->whenLoaded('customer', fn () => [
                'name' => $this->customer?->fullName() ?: $this->customer?->user?->name,
                'phone' => $this->customer?->user?->phone,
            ]),
            'items' => OrderItemResource::collection($this->whenLoaded('items')),
        ];
    }
}
