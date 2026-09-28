<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One line of an order — a dish, snapshotted AS SOLD (name + unit price), so a
 * later menu edit never rewrites order history.
 *
 * No merchant_id column, so no tenant scope: an order item is reached only
 * through its parent Order, which is already tenant-scoped.
 */
#[Fillable([
    'order_id', 'menu_item_id', 'name', 'unit_price', 'quantity', 'line_total',
])]
class OrderItem extends Model
{
    use HasFactory;

    protected function casts(): array
    {
        return [
            'unit_price' => 'decimal:2',
            'line_total' => 'decimal:2',
            'quantity' => 'integer',
        ];
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function options(): HasMany
    {
        return $this->hasMany(OrderItemOption::class);
    }

    /**
     * The live menu item, if it still exists — used only to show a thumbnail on
     * the orders list. Nullable: the FK nulls on delete, and history never
     * depends on it (the snapshot columns are the source of truth).
     */
    public function menuItem(): BelongsTo
    {
        return $this->belongsTo(MenuItem::class);
    }
}
