<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use App\Domain\Ordering\Events\OrderStatusChanged;
use App\Domain\Ordering\Exceptions\InvalidOrderTransition;
use App\Domain\Ordering\OrderStatus;
use App\Support\TokenGenerator;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A restaurant order (RestaurantEngine, R3).
 *
 * Money and status are the server's to set — never mass-assigned from a
 * request. Totals are computed in OrderService; status only ever moves through
 * transitionTo(), which validates against OrderStatus.
 */
#[Fillable([
    'branch_id', 'customer_id', 'fulfillment_type', 'table_number',
    'customer_notes', 'source',
])]
class Order extends Model
{
    use BelongsToTenant, HasFactory;

    protected $attributes = [
        'status' => 'placed',
        'fulfillment_type' => 'pickup',
        'subtotal' => 0,
        'total' => 0,
        'source' => 'app',
    ];

    protected function casts(): array
    {
        return [
            'status' => OrderStatus::class,
            'subtotal' => 'decimal:2',
            'delivery_fee' => 'decimal:2',
            'tax_rate' => 'decimal:2',
            'tax_amount' => 'decimal:2',
            'total' => 'decimal:2',
            'delivery_latitude' => 'decimal:8',
            'delivery_longitude' => 'decimal:8',
            'prep_minutes' => 'integer',
            'accepted_at' => 'immutable_datetime',
            'ready_at' => 'immutable_datetime',
            'completed_at' => 'immutable_datetime',
            'cancelled_at' => 'immutable_datetime',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (Order $order): void {
            $order->reference ??= TokenGenerator::uniqueBookingReference(self::class);
        });
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function items(): HasMany
    {
        return $this->hasMany(OrderItem::class);
    }

    /**
     * Move to a new status, or refuse. The ONLY way status changes.
     *
     * @throws InvalidOrderTransition
     */
    public function transitionTo(
        OrderStatus $target,
        string $actorType = 'system',
        array $extra = [],
    ): self {
        $current = $this->status;

        if (! $current->canTransitionTo($target)) {
            throw new InvalidOrderTransition($current, $target);
        }

        $this->status = $target;

        match ($target) {
            OrderStatus::Accepted => $this->accepted_at = CarbonImmutable::now(),
            OrderStatus::Ready => $this->ready_at = CarbonImmutable::now(),
            OrderStatus::Completed => $this->completed_at = CarbonImmutable::now(),
            OrderStatus::Cancelled, OrderStatus::Rejected => $this->cancelled_at = CarbonImmutable::now(),
            default => null,
        };

        foreach ($extra as $key => $value) {
            $this->setAttribute($key, $value);
        }

        $this->save();

        OrderStatusChanged::dispatch($this, $current, $target, $actorType);

        return $this;
    }

    /** Live orders the kitchen still has to act on. */
    public function scopeActive($query)
    {
        return $query->whereIn('status', [
            OrderStatus::Placed->value,
            OrderStatus::Accepted->value,
            OrderStatus::Preparing->value,
            OrderStatus::Ready->value,
        ]);
    }
}
