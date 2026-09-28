<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One chosen option on an order line, snapshotted as sold. */
#[Fillable([
    'order_item_id', 'menu_option_id', 'group_name', 'name', 'price_delta',
])]
class OrderItemOption extends Model
{
    use HasFactory;

    protected function casts(): array
    {
        return ['price_delta' => 'decimal:2'];
    }

    public function orderItem(): BelongsTo
    {
        return $this->belongsTo(OrderItem::class);
    }
}
