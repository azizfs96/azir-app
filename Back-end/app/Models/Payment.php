<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A payment attempt or refund (spec §20).
 * Provider-agnostic: swapping providers touches the provider class only.
 */
#[Fillable([
    'booking_id', 'provider', 'provider_payment_id', 'type', 'amount', 'currency',
    'status', 'method', 'failure_reason', 'raw_response', 'idempotency_key',
    'refund_of_payment_id',
])]
class Payment extends Model
{
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return [
            'amount' => 'decimal:2',
            'raw_response' => 'array',
            'paid_at' => 'immutable_datetime',
            'refunded_at' => 'immutable_datetime',
        ];
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }

    public function isSuccessful(): bool
    {
        return $this->status === 'captured';
    }
}
