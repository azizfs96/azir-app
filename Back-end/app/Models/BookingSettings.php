<?php

namespace App\Models;

use App\Domain\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * The configurable booking engine's settings (spec §9, §10, §21, §22).
 *
 * This row is what the customer app adapts to. The BeautyWellnessEngine reads it
 * and emits the ordered step list Flutter walks (ARCHITECTURE.md §2.2), which is
 * how one app binary serves every merchant.
 */
#[Fillable([
    'store_id', 'staff_selection', 'branch_selection', 'payment_required',
    'deposit_required', 'customer_notes', 'guest_booking', 'allow_cancellation',
    'order_pickup', 'order_dine_in', 'order_delivery', 'order_curbside',
    'delivery_fee', 'delivery_min_order', 'auto_accept_orders', 'default_prep_minutes',
    'tax_enabled', 'tax_rate', 'tax_number', 'legal_name', 'national_address', 'commercial_registration',
    'allow_rescheduling', 'deposit_type', 'deposit_value',
    'cancellation_deadline_hours', 'refund_policy', 'reschedule_deadline_hours',
    'auto_confirm', 'min_lead_time_minutes', 'max_advance_days', 'reminder_hours_before',
])]
class BookingSettings extends Model
{
    use BelongsToTenant, HasFactory;

    protected $table = 'booking_settings';

    protected function casts(): array
    {
        return [
            'staff_selection' => 'boolean',
            'branch_selection' => 'boolean',
            'payment_required' => 'boolean',
            'deposit_required' => 'boolean',
            'customer_notes' => 'boolean',
            'guest_booking' => 'boolean',
            'allow_cancellation' => 'boolean',
            'allow_rescheduling' => 'boolean',
            'auto_confirm' => 'boolean',
            'order_pickup' => 'boolean',
            'order_dine_in' => 'boolean',
            'order_delivery' => 'boolean',
            'order_curbside' => 'boolean',
            'delivery_fee' => 'decimal:2',
            'delivery_min_order' => 'decimal:2',
            'auto_accept_orders' => 'boolean',
            'default_prep_minutes' => 'integer',
            'tax_enabled' => 'boolean',
            'tax_rate' => 'decimal:2',
            'deposit_value' => 'decimal:2',
            'cancellation_deadline_hours' => 'integer',
            'reschedule_deadline_hours' => 'integer',
            'min_lead_time_minutes' => 'integer',
            'max_advance_days' => 'integer',
            'reminder_hours_before' => 'integer',
        ];
    }

    public function store(): BelongsTo
    {
        return $this->belongsTo(Store::class);
    }

    /**
     * The deposit due on a given price (spec §10).
     * Never more than the full price — a misconfigured 150% deposit would
     * otherwise charge more than the service costs.
     */
    public function depositFor(float $price): float
    {
        if (! $this->deposit_required) {
            return 0.0;
        }

        $amount = $this->deposit_type === 'percent'
            ? $price * ((float) $this->deposit_value / 100)
            : (float) $this->deposit_value;

        return round(min($amount, $price), 2);
    }

    /**
     * The §10 configuration object, exactly as the customer app consumes it (§31).
     *
     * @return array<string, bool>
     */
    public function toConfiguration(): array
    {
        return [
            'staff_selection' => $this->staff_selection,
            'branch_selection' => $this->branch_selection,
            'payment_required' => $this->payment_required,
            'deposit_required' => $this->deposit_required,
            'allow_cancellation' => $this->allow_cancellation,
            'allow_rescheduling' => $this->allow_rescheduling,
            'customer_notes' => $this->customer_notes,
            'guest_booking' => $this->guest_booking,
        ];
    }

    /**
     * Platform defaults for a brand-new store — the fastest path to a working
     * QR (spec §11: do not overcomplicate merchant setup).
     *
     * @return array<string, mixed>
     */
    public static function defaults(): array
    {
        return [
            'staff_selection' => false,
            'branch_selection' => false,
            'payment_required' => false,
            'deposit_required' => false,
            'customer_notes' => true,
            'guest_booking' => false,
            'allow_cancellation' => true,
            'allow_rescheduling' => true,
            'deposit_type' => 'percent',
            'deposit_value' => 25.00,
            'cancellation_deadline_hours' => 4,
            'refund_policy' => 'deposit_forfeited',
            'reschedule_deadline_hours' => 4,
            'auto_confirm' => true,
            'min_lead_time_minutes' => 60,
            'max_advance_days' => 60,
            'reminder_hours_before' => 24,
        ];
    }
}
