<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Append-only transition log (spec §19). Never updated, never deleted. */
#[Fillable(['booking_id', 'from_status', 'to_status', 'changed_by_user_id', 'actor_type', 'reason'])]
class BookingStatusHistory extends Model
{
    protected $table = 'booking_status_history';

    public $timestamps = false;

    protected function casts(): array
    {
        return ['created_at' => 'immutable_datetime'];
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }

    public function changedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'changed_by_user_id');
    }
}
