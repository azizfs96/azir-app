<?php

namespace App\Domain\Booking;

use App\Domain\Booking\Events\BookingRescheduled;
use App\Domain\Booking\Exceptions\SlotNoLongerAvailable;
use App\Domain\Scheduling\AvailabilityEngine;
use App\Domain\Scheduling\StaffAssigner;
use App\Models\Booking;
use App\Models\Branch;
use App\Models\Customer;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use Carbon\CarbonImmutable;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;

/**
 * Creating, cancelling and rescheduling bookings.
 *
 * ============================================================================
 * THE DOUBLE-BOOKING GUARD (ARCHITECTURE.md §6.3)
 *
 * AvailabilityEngine::slotsFor() is ADVISORY — two customers can both be shown
 * 19:00 at the same instant. What actually prevents a double booking is here:
 *
 *   1. open a transaction
 *   2. SELECT ... FOR UPDATE on the STAFF row (or the branch row when the
 *      branch is the resource) — this serialises every concurrent attempt for
 *      that resource
 *   3. re-run the conflict check INSIDE the lock, because the availability the
 *      customer saw may be seconds stale
 *   4. only then insert
 *
 * MySQL has no exclusion constraints, so a row lock is the serialisation
 * point. Contention is per-staff and held for milliseconds.
 * ============================================================================
 */
class BookingService
{
    /**
     * How many times a transaction may be replayed after a deadlock.
     *
     * With consistent lock ordering deadlocks should not occur at all; this is
     * a bounded safety net for contention the ordering cannot cover (for
     * example a concurrent schema-touching migration), never an infinite loop.
     */
    private const DEADLOCK_RETRIES = 3;

    public function __construct(
        private readonly AvailabilityEngine $availability,
        private readonly StaffAssigner $staffAssigner,
    ) {}

    /**
     * @param  array<string, mixed>  $attributes
     *
     * @throws SlotNoLongerAvailable
     */
    public function create(
        Store $store,
        Service $service,
        CarbonImmutable $startsAt,
        ?Branch $branch = null,
        ?Staff $requestedStaff = null,
        ?Customer $customer = null,
        array $attributes = [],
    ): Booking {
        $branch ??= $store->defaultBranch();

        if ($branch === null) {
            throw new SlotNoLongerAvailable('This store has no bookable branch.');
        }

        $settings = $store->bookingSettings;

        $duration = $requestedStaff !== null
            ? $requestedStaff->durationFor($service)
            : $service->duration_minutes;

        $endsAt = $startsAt->addMinutes($duration + $service->buffer_after_minutes);

        /*
         * The second argument is Laravel's built-in bounded retry: on a
         * deadlock or serialization failure the whole transaction is rolled
         * back and re-run, at most this many times. The closure re-reads and
         * re-checks everything, so a retry is safe; the bound stops it looping.
         */
        return DB::transaction(function () use (
            $store, $service, $branch, $requestedStaff, $customer,
            $startsAt, $endsAt, $duration, $settings, $attributes
        ): Booking {
            /*
             * Step 2 — take the lock BEFORE checking anything.
             *
             * BOTH PATHS MUST LOCK THE SAME KIND OF ROW, IN THE SAME ORDER.
             *
             * They previously did not: the explicit path locked a `staff` row
             * while the auto-assign path locked a `branches` row. Two requests
             * competing for the same stylist therefore held different locks and
             * both passed the availability check below — no mutual exclusion at
             * all. What saved the data was accidental: the INSERT takes foreign
             * key shared locks on BOTH parents, so the two transactions formed
             * a cycle and InnoDB killed one:
             *
             *     A: holds X on staff    -> waits S on branches (FK)
             *     B: holds X on branches -> waits S on staff    (FK)
             *
             * The customer received a raw SQL deadlock as a 500. Locking staff
             * rows on every path removes the cycle and makes the exclusion real.
             */
            $staff = $requestedStaff;

            if ($staff !== null) {
                Staff::whereKey($staff->id)->lockForUpdate()->first();
            } else {
                /*
                 * Auto-assignment: lock every stylist who could be chosen,
                 * ascending by id, BEFORE deciding. Ascending order is what
                 * keeps concurrent auto-assignments deadlock-free, and holding
                 * the whole candidate set is what stops two requests being
                 * handed the same person.
                 */
                $this->lockCandidateStaff($store);

                $staff = $this->staffAssigner->assign(
                    $store, $service, $branch, $startsAt, $endsAt, $this->availability,
                );

                // A store with no staff at all books against the branch itself
                // (spec §15) — that is legitimate, so a null staff is only fatal
                // when the store does employ people and none of them are free.
                if ($staff === null) {
                    if ($this->storeEmploysStaff($store)) {
                        throw new SlotNoLongerAvailable('No staff member is available at that time.');
                    }

                    // Branch IS the bookable resource here. No staff row exists
                    // to lock, and no staff FK is written, so locking the branch
                    // cannot form the cycle described above.
                    Branch::whereKey($branch->id)->lockForUpdate()->first();
                }
            }

            /*
             * Step 3a — is this a slot the business could EVER serve?
             *
             * Working hours, rosters, time off, capability, branch membership
             * and the booking window. Availability already refuses to display
             * such times; without this the write path accepted them anyway
             * (probes booked 03:00, vacations, the past, and 90 days out).
             */
            $violation = $this->availability->violationFor(
                $store, $service, $branch, $staff, $startsAt, $endsAt,
            );

            if ($violation !== null) {
                throw new SlotNoLongerAvailable('This time cannot be booked: '.$violation.'.');
            }

            // Step 3b — re-verify under the lock. This is the authoritative check.
            if (! $this->availability->isStillFree($staff, $branch, $startsAt, $endsAt)) {
                throw new SlotNoLongerAvailable('That time was just booked.');
            }

            /*
             * Step 4 — insert.
             *
             * merchant_id is forceFilled from the resolved store rather than
             * left to the BelongsToTenant auto-fill, because the common case is
             * a CUSTOMER booking: they authenticate as role=customer and carry
             * no tenant context at all, so there would be nothing to fill from.
             * The store is trusted server-side data, so it is the right source
             * either way — and it keeps merchant_id out of $fillable, where a
             * request payload could reach it.
             */
            $booking = new Booking(array_merge([
                'store_id' => $store->id,
                'branch_id' => $branch->id,
                'customer_id' => $customer?->id,
                'service_id' => $service->id,
                'staff_id' => $staff?->id,
                'starts_at' => $startsAt->utc(),
                'ends_at' => $endsAt->utc(),
                'duration_minutes' => $duration,
                'price' => $service->price,
                'currency' => $service->currency,
                // Deposits are recorded but never charged while online payment
                // is off (config wasla.payments.online_enabled).
                'deposit_amount' => $settings?->depositFor((float) $service->price) ?? 0,
            ], $attributes));

            /*
             * The unique index on active_slot_key is the database's own guard
             * (see the 2026_01_02 migration). If the lock above ever fails to
             * exclude a competitor, the INSERT is refused here — and the
             * customer must still see the documented 409 SLOT_TAKEN, never a
             * SQL string.
             */
            try {
                $booking->forceFill(['merchant_id' => $store->merchant_id])->save();
            } catch (UniqueConstraintViolationException) {
                throw new SlotNoLongerAvailable('That time was just booked.');
            }

            // Most merchants auto-confirm; those who vet bookings leave it pending.
            if ($settings?->auto_confirm) {
                $booking->transitionTo(BookingStatus::Confirmed, 'system');
            }

            return $booking;
        }, attempts: self::DEADLOCK_RETRIES);
    }

    /**
     * Customer-initiated cancellation, honouring the merchant's policy (§21).
     */
    public function cancelAsCustomer(Booking $booking, ?string $reason = null, ?int $userId = null): Booking
    {
        if (! $booking->isCancellableByCustomer()) {
            throw new SlotNoLongerAvailable('This booking can no longer be cancelled.');
        }

        return $booking->transitionTo(BookingStatus::Cancelled, 'customer', $userId, $reason);
    }

    /**
     * Move a booking to a new time (§22).
     *
     * "The system must re-check availability before confirming" — so this runs
     * through the same lock-and-verify path as a fresh booking, ignoring the
     * booking being moved so it does not conflict with itself.
     *
     * @throws SlotNoLongerAvailable
     */
    public function reschedule(
        Booking $booking,
        CarbonImmutable $startsAt,
        ?Staff $requestedStaff = null,
        ?int $userId = null,
    ): Booking {
        if (! $booking->isReschedulableByCustomer()) {
            throw new SlotNoLongerAvailable('This booking can no longer be rescheduled.');
        }

        // Explicit loads: reschedule may be reached with a bare model, and the
        // validation below needs the service and settings.
        $booking->loadMissing(['service', 'store.bookingSettings', 'branch', 'staff']);

        $branch = $booking->branch ?? $booking->store->defaultBranch();
        $staff = $requestedStaff ?? $booking->staff;
        $endsAt = $startsAt->addMinutes($booking->duration_minutes);

        return DB::transaction(function () use ($booking, $branch, $staff, $startsAt, $endsAt, $userId): Booking {
            // Same rule as create(): lock the STAFF row when a stylist is
            // involved, so a reschedule and a fresh booking competing for the
            // same person contend on the same row instead of deadlocking.
            if ($staff !== null) {
                Staff::whereKey($staff->id)->lockForUpdate()->first();
            } elseif ($branch !== null) {
                Branch::whereKey($branch->id)->lockForUpdate()->first();
            }

            /*
             * A reschedule is a fresh booking at the new time and must pass
             * the same static validity — hours, roster, time off, capability,
             * window. It previously re-checked only booking collisions, so a
             * customer could move an appointment to 03:00 or into the past.
             */
            $violation = $this->availability->violationFor(
                $booking->store, $booking->service, $branch, $staff, $startsAt, $endsAt,
            );

            if ($violation !== null) {
                throw new SlotNoLongerAvailable('This time cannot be booked: '.$violation.'.');
            }

            $free = $this->availability->isStillFree(
                $staff, $branch, $startsAt, $endsAt, ignoreBookingId: $booking->id,
            );

            if (! $free) {
                throw new SlotNoLongerAvailable('That time is not available.');
            }

            $previousStartsAt = $booking->starts_at;

            $booking->starts_at = $startsAt->utc();
            $booking->ends_at = $endsAt->utc();
            $booking->staff_id = $staff?->id;

            try {
                $booking->save();
            } catch (UniqueConstraintViolationException) {
                throw new SlotNoLongerAvailable('That time is not available.');
            }

            BookingRescheduled::dispatch($booking, $previousStartsAt);

            $booking->statusHistory()->create([
                'from_status' => $booking->booking_status->value,
                'to_status' => $booking->booking_status->value,
                'changed_by_user_id' => $userId,
                'actor_type' => 'customer',
                'reason' => 'Rescheduled',
            ]);

            return $booking;
        }, attempts: self::DEADLOCK_RETRIES);
    }

    private function storeEmploysStaff(Store $store): bool
    {
        return Staff::query()->where('store_id', $store->id)->bookable()->exists();
    }

    /**
     * Lock every stylist this store could auto-assign, ascending by id.
     *
     * A superset of the assigner's candidates on purpose: whoever it ends up
     * choosing is already locked, so no second request can be handed the same
     * person between the decision and the insert.
     *
     * The ORDER is the important part. Every transaction that locks more than
     * one staff row takes them in the same ascending sequence, which is what
     * makes concurrent auto-assignments queue instead of deadlocking.
     *
     * Contention is bounded by the size of one salon's roster and the lock is
     * held for the few milliseconds of the surrounding transaction.
     */
    private function lockCandidateStaff(Store $store): void
    {
        Staff::query()
            ->where('store_id', $store->id)
            ->bookable()
            ->orderBy('id')
            ->lockForUpdate()
            ->pluck('id');
    }
}
