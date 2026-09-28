<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use InvalidArgumentException;

/**
 * Ad-hoc closure overriding the weekly schedule — a staff holiday or a whole
 * branch closing for Eid.
 *
 * Exactly one of staff_id / branch_id must be set. MySQL CHECK support is not
 * something to rely on across versions, so it is enforced here instead.
 */
#[Fillable(['staff_id', 'branch_id', 'starts_at', 'ends_at', 'reason', 'is_recurring_annual'])]
class TimeOff extends Model
{
    use BelongsToTenant, HasFactory;

    protected $table = 'time_off';

    protected function casts(): array
    {
        return [
            'starts_at' => 'immutable_datetime',
            'ends_at' => 'immutable_datetime',
            'is_recurring_annual' => 'boolean',
        ];
    }

    protected static function booted(): void
    {
        static::saving(function (TimeOff $timeOff): void {
            $hasStaff = $timeOff->staff_id !== null;
            $hasBranch = $timeOff->branch_id !== null;

            if ($hasStaff === $hasBranch) {
                throw new InvalidArgumentException(
                    'Time off must target exactly one of staff_id or branch_id.'
                );
            }
        });
    }

    public function staff(): BelongsTo
    {
        return $this->belongsTo(Staff::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }
}
