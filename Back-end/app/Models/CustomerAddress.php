<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Facades\DB;

/**
 * A delivery address a customer saved in the app (feature expansion).
 *
 * Belongs to the PLATFORM customer, never to a store — a store only ever reads
 * the one address the customer chose at checkout, and the order snapshots it.
 * Deliberately NOT tenant-scoped, exactly like Customer (ARCHITECTURE.md §5.2).
 */
#[Fillable(['customer_id', 'label', 'address_text', 'details', 'latitude', 'longitude', 'is_default'])]
class CustomerAddress extends Model
{
    use HasFactory;

    protected function casts(): array
    {
        return [
            'latitude' => 'decimal:8',
            'longitude' => 'decimal:8',
            'is_default' => 'boolean',
        ];
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    /**
     * Make this the customer's default, demoting every other one in a single
     * cheap UPDATE — the invariant "exactly one default" lives here, not in a DB
     * constraint MySQL cannot express cleanly.
     */
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
