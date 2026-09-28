<?php

namespace App\Console\Commands;

use App\Domain\Booking\BookingStatus;
use App\Domain\Notification\NotificationDispatcher;
use App\Models\Booking;
use Carbon\CarbonImmutable;
use Illuminate\Console\Command;

/**
 * Appointment reminders (spec §23).
 *
 * Each store sets its own reminder_hours_before, so this cannot be a single
 * "24 hours from now" query — it compares each booking against ITS store's
 * configured lead time.
 *
 * Runs every 15 minutes. reminder_sent_at makes it idempotent, so a re-run
 * after a failure never double-notifies.
 */
class SendAppointmentReminders extends Command
{
    protected $signature = 'wasla:send-reminders';

    protected $description = 'Send reminders for upcoming appointments';

    public function handle(NotificationDispatcher $dispatcher): int
    {
        $now = CarbonImmutable::now();

        $bookings = Booking::query()
            ->withoutTenancy()
            ->whereNull('reminder_sent_at')
            ->where('starts_at', '>', $now)
            // Widest possible window; the per-store check below narrows it.
            ->where('starts_at', '<=', $now->addDays(7))
            ->whereIn('booking_status', [
                BookingStatus::Pending->value,
                BookingStatus::Confirmed->value,
            ])
            ->with(['store.bookingSettings', 'service', 'customer.user'])
            ->limit(500)
            ->get();

        $sent = 0;

        foreach ($bookings as $booking) {
            $hours = $booking->store?->bookingSettings?->reminder_hours_before ?? 24;

            // Not due yet.
            if ($booking->starts_at->greaterThan($now->addHours($hours))) {
                continue;
            }

            $dispatcher->bookingEvent($booking, 'booking_reminder');

            $booking->forceFill(['reminder_sent_at' => $now])->save();
            $sent++;
        }

        $this->info("Sent {$sent} reminder(s).");

        return self::SUCCESS;
    }
}
