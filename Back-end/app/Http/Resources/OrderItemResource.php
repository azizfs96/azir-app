<?php

namespace App\Http\Resources;

use App\Models\OrderItem;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @property OrderItem $resource */
class OrderItemResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            // The menu ids let the app rebuild this line into the cart for a
            // reorder; the server still revalidates and reprices at order time.
            'item_id' => $this->menu_item_id,
            'name' => $this->name,
            'image' => $this->whenLoaded('menuItem', fn () => $this->menuItem?->image_path),
            'unit_price' => (float) $this->unit_price,
            'quantity' => $this->quantity,
            'line_total' => (float) $this->line_total,
            'options' => $this->whenLoaded('options', fn () => $this->options->map(fn ($o) => [
                'option_id' => $o->menu_option_id,
                'group' => $o->group_name,
                'name' => $o->name,
                'price_delta' => (float) $o->price_delta,
            ])->values()),
        ];
    }
}
