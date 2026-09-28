<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Per-staff working hours and break for one weekday (spec §15). */
#[Fillable([
    'staff_id', 'day_of_week', 'starts_at', 'ends_at',
    'break_starts_at', 'break_ends_at', 'is_off',
])]
class StaffSchedule extends Model
{
    use HasFactory;

    protected function casts(): array
    {
        return ['is_off' => 'boolean', 'day_of_week' => 'integer'];
    }

    public function staff(): BelongsTo
    {
        return $this->belongsTo(Staff::class);
    }

    public function hasBreak(): bool
    {
        return $this->break_starts_at !== null && $this->break_ends_at !== null;
    }
}
