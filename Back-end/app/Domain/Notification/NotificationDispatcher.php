<?php

namespace App\Domain\Notification;

use App\Models\Booking;
use App\Models\Order;
use App\Models\User;
use App\Models\WaslaNotification;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Log;

/**
 * ============================================================================
 * NOTIFICATIONS (spec §23)
 *
 * MVP events:  booking confirmed · cancelled · rescheduled · reminder · completed
 * MVP channels: push + in-app.  SMS and WhatsApp arrive later.
 *
 * "Create a notification architecture that supports push, email, SMS later,
 *  WhatsApp later."
 *
 * The architecture that makes "later" cheap is this: the booking engine emits
 * DOMAIN EVENTS and knows nothing about delivery. Adding WhatsApp means writing
 * one channel class — no change to any code that creates or cancels a booking.
 *
 * Every send is recorded in wasla_notifications as template_key + payload
 * rather than a rendered string, so the same record renders in Arabic or
 * English depending on who reads it (spec §33).
 * ============================================================================
 */
class NotificationDispatcher
{
    /**
     * @param  array<int, NotificationChannel>  $channels
     */
    public function __construct(private readonly array $channels) {}

    /**
     * Notify the customer about something that happened to their booking.
     */
    public function bookingEvent(Booking $booking, string $templateKey): void
    {
        $user = $booking->customer?->user;

        if ($user === null) {
            // Guest booking: no account, so nothing to push to. SMS would cover
            // this once a provider is wired up (§13 decision 2).
            return;
        }

        $store = $booking->store;
        $locale = $user->locale ?: 'ar';

        $payload = [
            'booking_id' => $booking->id,
            'reference' => $booking->reference,
            'store_name' => $store?->displayName($locale),
            'store_token' => $store?->public_token,
            'service_name' => $booking->service?->displayName($locale),
            'starts_at' => $booking->starts_at->setTimezone($store?->timezone ?? 'UTC')->toIso8601String(),
            'time' => $booking->starts_at->setTimezone($store?->timezone ?? 'UTC')->format('H:i'),
            'date' => $booking->starts_at->setTimezone($store?->timezone ?? 'UTC')->format('Y-m-d'),
        ];

        $this->send($user, $booking, $templateKey, $payload, $locale);
    }

    /**
     * Notify the customer about something that happened to their order.
     *
     * Mirrors bookingEvent: the ordering engine emits a domain event and knows
     * nothing about delivery — a listener turns it into "order accepted / ready"
     * for the customer, in their own locale.
     */
    public function orderEvent(Order $order, string $templateKey): void
    {
        $user = $order->customer?->user;

        if ($user === null) {
            // Guest order: no account to push to (SMS would cover this later).
            return;
        }

        $store = $order->store;
        $locale = $user->locale ?: 'ar';

        $payload = [
            'order_id' => $order->id,
            'reference' => $order->reference,
            'store_name' => $store?->displayName($locale),
            'store_token' => $store?->public_token,
        ];

        $this->send($user, null, $templateKey, $payload, $locale, $order);
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    public function send(
        User $user,
        ?Booking $booking,
        string $templateKey,
        array $payload,
        string $locale = 'ar',
        ?Order $order = null,
    ): void {
        $title = __("notifications.{$templateKey}.title", $payload, $locale);
        $body = __("notifications.{$templateKey}.body", $payload, $locale);

        foreach ($this->channels as $channel) {
            $record = new WaslaNotification;

            $record->forceFill([
                'notifiable_type' => User::class,
                'notifiable_id' => $user->id,
                'channel' => $channel->key(),
                'template_key' => $templateKey,
                'payload' => $payload,
                'locale' => $locale,
                'booking_id' => $booking?->id,
                'order_id' => $order?->id,
                'status' => 'queued',
            ])->save();

            try {
                $channel->send($user, $title, $body, $payload);

                $record->forceFill([
                    'status' => 'sent',
                    'sent_at' => CarbonImmutable::now(),
                ])->save();
            } catch (\Throwable $e) {
                /*
                 * A failed notification must never fail the booking.
                 *
                 * The customer's appointment is already committed; if push
                 * delivery breaks, that is an operational problem to observe,
                 * not a reason to roll back their reservation.
                 */
                $record->forceFill([
                    'status' => 'failed',
                    'failure_reason' => substr($e->getMessage(), 0, 250),
                ])->save();

                Log::warning('[notification] delivery failed', [
                    'channel' => $channel->key(),
                    'template' => $templateKey,
                    'error' => $e->getMessage(),
                ]);
            }
        }
    }
}
