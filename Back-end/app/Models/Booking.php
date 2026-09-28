<?php

namespace App\Models;

use App\Domain\Booking\BookingStatus;
use App\Domain\Booking\Events\BookingStatusChanged;
use App\Domain\Booking\Exceptions\InvalidStatusTransition;
use App\Domain\Concerns\BelongsToTenant;
use App\Support\TokenGenerator;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * A booking (spec §18, §19).
 *
 * Timestamps are UTC; render them through the store's timezone (§5.4).
 * Price is snapshotted at creation so later price edits never rewrite history.
 */
#[Fillable([
    'store_id', 'branch_id', 'customer_id', 'service_id', 'staff_id',
    'guest_name', 'guest_phone', 'starts_at', 'ends_at', 'duration_minutes',
    'price', 'deposit_amount', 'currency', 'customer_notes', 'source', 'metadata',
])]
class Booking extends Model
{
    use BelongsToTenant, HasFactory, SoftDeletes;

    /**
     * Defaults must exist in PHP, not only as DB column defaults.
     *
     * Without these, a freshly created Booking has a NULL booking_status in
     * memory for the rest of the request — so the very first transitionTo()
     * after create() fatals on null. The database would have said 'pending'
     * all along; the model has to agree before it reloads.
     */
    protected $attributes = [
        'booking_status' => 'pending',
        'payment_status' => 'unpaid',
        'paid_amount' => 0,
        'deposit_amount' => 0,
        'source' => 'app',
        'currency' => 'SAR',
    ];

    protected function casts(): array
    {
        return [
            'starts_at' => 'immutable_datetime',
            'ends_at' => 'immutable_datetime',
            'cancelled_at' => 'immutable_datetime',
            'checked_in_at' => 'immutable_datetime',
            'completed_at' => 'immutable_datetime',
            'reminder_sent_at' => 'immutable_datetime',
            'booking_status' => BookingStatus::class,
            'price' => 'decimal:2',
            'deposit_amount' => 'decimal:2',
            'paid_amount' => 'decimal:2',
            'duration_minutes' => 'integer',
            'metadata' => 'array',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (Booking $booking): void {
            $booking->reference ??= TokenGenerator::uniqueBookingReference(self::class);
        });
    }

    // ---- Relations ----

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

    public function service(): BelongsTo
    {
        return $this->belongsTo(Service::class);
    }

    public function staff(): BelongsTo
    {
        return $this->belongsTo(Staff::class);
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }

    public function statusHistory(): HasMany
    {
        return $this->hasMany(BookingStatusHistory::class);
    }

    // ---- State machine (spec §19) ----

    /**
     * Move to a new status, or refuse.
     *
     * Every transition is validated against BookingStatus and recorded in
     * booking_status_history. This is the ONLY way status changes — nothing
     * should ever assign ->booking_status directly.
     *
     * @throws InvalidStatusTransition
     */
    public function transitionTo(
        BookingStatus $target,
        string $actorType = 'system',
        ?int $userId = null,
        ?string $reason = null,
    ): self {
        $current = $this->booking_status;

        if (! $current->canTransitionTo($target)) {
            throw new InvalidStatusTransition($current, $target);
        }

        $this->booking_status = $target;

        /*
         * Denormalised timestamps for the dashboard, so common queries don't
         * have to join history.
         *
         * Assigned directly rather than via fill(): these are internal state,
         * deliberately absent from $fillable so no request payload can ever set
         * them. Domain code is allowed to; a controller is not.
         */
        match ($target) {
            BookingStatus::CheckedIn => $this->checked_in_at = CarbonImmutable::now(),
            BookingStatus::Completed => $this->completed_at = CarbonImmutable::now(),
            BookingStatus::Cancelled => $this->setCancellationFields($actorType, $reason),
            default => null,
        };

        $this->save();

        $this->statusHistory()->create([
            'from_status' => $current->value,
            'to_status' => $target->value,
            'changed_by_user_id' => $userId,
            'actor_type' => $actorType,
            'reason' => $reason,
        ]);

        /*
         * Announce, do not deliver.
         *
         * The booking engine has no idea a notification exists — it fires an
         * event and moves on. That is what lets SMS and WhatsApp be added later
         * without touching a single line of booking code (spec §23).
         */
        BookingStatusChanged::dispatch($this, $current, $target, $actorType);

        return $this;
    }

    private function setCancellationFields(string $actorType, ?string $reason): void
    {
        $this->cancelled_at = CarbonImmutable::now();
        $this->cancelled_by = $actorType;
        $this->cancellation_reason = $reason;
    }

    // ---- Policy checks (spec §21, §22) ----

    /**
     * May the customer still cancel? Both the merchant's toggle and the
     * deadline must allow it.
     */
    public function isCancellableByCustomer(?CarbonImmutable $now = null): bool
    {
        $settings = $this->store->bookingSettings;

        if (! $settings?->allow_cancellation) {
            return false;
        }

        if (! $this->booking_status->isCustomerCancellable()) {
            return false;
        }

        return $this->isBeforeDeadline($settings->cancellation_deadline_hours, $now);
    }

    public function isReschedulableByCustomer(?CarbonImmutable $now = null): bool
    {
        $settings = $this->store->bookingSettings;

        if (! $settings?->allow_rescheduling) {
            return false;
        }

        if (! $this->booking_status->isCustomerCancellable()) {
            return false;
        }

        return $this->isBeforeDeadline($settings->reschedule_deadline_hours, $now);
    }

    /**
     * Is `now` still earlier than (appointment - deadline)?
     */
    private function isBeforeDeadline(int $deadlineHours, ?CarbonImmutable $now = null): bool
    {
        $now ??= CarbonImmutable::now();

        return $now->lessThan($this->starts_at->subHours($deadlineHours));
    }

    /**
     * The refund due if cancelled right now, per the merchant's policy (§21).
     */
    public function refundableAmount(): float
    {
        $settings = $this->store->bookingSettings;
        $paid = (float) $this->paid_amount;

        return match ($settings?->refund_policy) {
            'full' => $paid,
            'deposit_forfeited' => max(0, round($paid - (float) $this->deposit_amount, 2)),
            default => 0.0,
        };
    }

    public function outstandingAmount(): float
    {
        return max(0, round((float) $this->price - (float) $this->paid_amount, 2));
    }

    // ---- Scopes ----

    /**
     * Bookings that occupy calendar time — the availability engine's filter.
     *
     * @param  Builder<Booking>  $query
     */
    public function scopeBlocking(Builder $query): Builder
    {
        return $query->whereIn('booking_status', BookingStatus::blockingValues());
    }

    /**
     * Overlap test: [starts_at, ends_at) intersects [$from, $to).
     *
     * Half-open on purpose — a booking ending at 15:00 must not conflict with
     * one starting at 15:00.
     *
     * @param  Builder<Booking>  $query
     */
    public function scopeOverlapping(Builder $query, CarbonImmutable $from, CarbonImmutable $to): Builder
    {
        return $query->where('starts_at', '<', $to)->where('ends_at', '>', $from);
    }

    /** @param  Builder<Booking>  $query */
    public function scopeUpcoming(Builder $query): Builder
    {
        return $query->where('starts_at', '>=', CarbonImmutable::now())
            ->whereIn('booking_status', [BookingStatus::Pending->value, BookingStatus::Confirmed->value]);
    }
}
