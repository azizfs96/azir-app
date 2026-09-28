<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Branch opening hours for one weekday. Multiple rows per day = split shifts
 * (prayer-time closures) — see the migration for why that matters.
 */
#[Fillable(['branch_id', 'day_of_week', 'opens_at', 'closes_at', 'is_closed'])]
class BranchSchedule extends Model
{
    use HasFactory;

    protected function casts(): array
    {
        return ['is_closed' => 'boolean', 'day_of_week' => 'integer'];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }
}
