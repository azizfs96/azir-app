<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Push registration (spec §23). One user, many devices. */
#[Fillable(['user_id', 'token', 'platform', 'app_version', 'device_model', 'last_seen_at'])]
class DeviceToken extends Model
{
    protected function casts(): array
    {
        return ['last_seen_at' => 'immutable_datetime'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
