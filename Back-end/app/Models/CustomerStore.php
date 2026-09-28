<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * "My Stores" (spec §5, §46).
 *
 * NOT tenant-scoped — it belongs to the customer, and spans merchants by
 * definition. A row exists only because the customer scanned or opened a link.
 */
#[Fillable([
    'customer_id', 'store_id', 'added_via', 'first_added_at',
    'last_visited_at', 'last_booking_at', 'is_hidden',
])]
class CustomerStore extends Model
{
    protected $table = 'customer_stores';

    protected function casts(): array
    {
        return [
            'first_added_at' => 'immutable_datetime',
            'last_visited_at' => 'immutable_datetime',
            'last_booking_at' => 'immutable_datetime',
            'is_hidden' => 'boolean',
        ];
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }
}
