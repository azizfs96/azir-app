<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Advanced/rare merchant options as JSON, so new ones need no migration. */
#[Fillable(['merchant_id', 'settings'])]
class MerchantSetting extends Model
{
    protected function casts(): array
    {
        return ['settings' => 'array'];
    }

    public function merchant(): BelongsTo
    {
        return $this->belongsTo(Merchant::class);
    }

    public function get(string $key, mixed $default = null): mixed
    {
        return data_get($this->settings, $key, $default);
    }
}
