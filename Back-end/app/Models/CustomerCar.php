<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\DB;

/**
 * A car a customer saved for curbside pickup ("من السيارة"). Central to the
 * platform customer, never tenant-scoped; a curbside order snapshots it.
 */
#[Fillable(['customer_id', 'brand', 'color', 'plate_letters', 'plate_numbers', 'is_default'])]
class CustomerCar extends Model
{
    use HasFactory;

    protected function casts(): array
    {
        return ['is_default' => 'boolean'];
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    /** "تويوتا أبيض · أ ب ج 4592" — the snapshot a curbside order keeps. */
    public function description(): string
    {
        return trim("{$this->brand} {$this->color} · {$this->plate_letters} {$this->plate_numbers}");
    }

    public function makeDefault(): void
    {
        DB::transaction(function (): void {
            static::query()
                ->where('customer_id', $this->customer_id)
                ->where('id', '!=', $this->id)
                ->update(['is_default' => false]);

            $this->forceFill(['is_default' => true])->save();
        });
    }
}
