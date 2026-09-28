<?php

namespace App\Models;

use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

/**
 * One-time passcode (spec §34). The code itself is only ever stored hashed.
 */
#[Fillable(['phone', 'code_hash', 'purpose', 'ip_hash', 'expires_at'])]
class OtpCode extends Model
{
    protected function casts(): array
    {
        return [
            'expires_at' => 'immutable_datetime',
            'consumed_at' => 'immutable_datetime',
            'attempts' => 'integer',
        ];
    }

    /** Live codes only: not yet used, not yet expired. */
    /** @param Builder<OtpCode> $query */
    public function scopeUsable(Builder $query): Builder
    {
        return $query->whereNull('consumed_at')
            ->where('expires_at', '>', CarbonImmutable::now());
    }

    public function isExhausted(): bool
    {
        return $this->attempts >= (int) config('wasla.otp.max_attempts', 5);
    }

    /**
     * Burn this code so it can never be used again.
     *
     * An explicit method rather than update(['consumed_at' => ...]): consumed_at
     * is deliberately not fillable, because nothing arriving from a request
     * should ever be able to mark a code as used.
     */
    public function consume(): void
    {
        $this->forceFill(['consumed_at' => CarbonImmutable::now()])->save();
    }
}
