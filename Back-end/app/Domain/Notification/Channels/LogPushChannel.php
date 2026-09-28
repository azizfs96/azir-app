<?php

namespace App\Domain\Notification\Channels;

use App\Domain\Notification\NotificationChannel;
use App\Models\User;
use Illuminate\Support\Facades\Log;

/**
 * Development push driver.
 *
 * Writes what WOULD be pushed to the log, so the whole notification pipeline is
 * exercisable without Firebase credentials or an APNs certificate. Swapping in
 * a real FcmPushChannel later touches this binding only (AppServiceProvider).
 */
class LogPushChannel implements NotificationChannel
{
    public function key(): string
    {
        return 'push';
    }

    public function send(User $user, string $title, string $body, array $payload): void
    {
        $devices = $user->deviceTokens()->pluck('token');

        if ($devices->isEmpty()) {
            // Not an error: plenty of users have never opened the app on a
            // device that registered for push.
            return;
        }

        Log::info('[push] '.$title.' :: '.$body, [
            'user_id' => $user->id,
            'devices' => $devices->count(),
            'booking_id' => $payload['booking_id'] ?? null,
        ]);
    }
}
