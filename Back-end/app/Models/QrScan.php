<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One scan event (spec §25). customer_id is null for the most interesting scan
 * of all: a brand new customer, before they authenticate.
 */
#[Fillable([
    'store_id', 'customer_id', 'session_id', 'ip_hash', 'user_agent',
    'platform', 'is_first_scan_for_customer', 'resulted_in_booking_id',
])]
class QrScan extends Model
{
    use BelongsToTenant;

    public $timestamps = false;

    protected function casts(): array
    {
        return [
            'is_first_scan_for_customer' => 'boolean',
            'scanned_at' => 'immutable_datetime',
        ];
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }
}
