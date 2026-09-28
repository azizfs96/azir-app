<?php

namespace App\Domain\Notification\Channels;

use App\Domain\Notification\Fcm\FcmClient;
use App\Domain\Notification\Fcm\FcmResult;
use App\Domain\Notification\NotificationChannel;
use App\Models\DeviceToken;
use App\Models\User;
use Illuminate\Support\Facades\Log;

/**
 * Production push driver (spec §23): delivers to every device the user has
 * registered, over Firebase Cloud Messaging.
 *
 * Replaces LogPushChannel. If Firebase is not configured (no service-account
 * file), it degrades to a log line so development and tests without credentials
 * behave exactly as before rather than erroring.
 *
 * A token FCM reports as unregistered is deleted on the spot — that is how the
 * device_tokens table stays clean as tokens rotate.
 */
class FcmPushChannel implements NotificationChannel
{
    public function __construct(private readonly FcmClient $fcm) {}

    public function key(): string
    {
        return 'push';
    }

    public function send(User $user, string $title, string $body, array $payload): void
    {
        /** @var \Illuminate\Database\Eloquent\Collection<int, DeviceToken> $devices */
        $devices = $user->deviceTokens()->get();

        if ($devices->isEmpty()) {
            // Not an error: many users have never registered a device.
            return;
        }

        if (! $this->fcm->isConfigured()) {
            Log::info('[push:unconfigured] '.$title.' :: '.$body, [
                'user_id' => $user->id,
                'devices' => $devices->count(),
            ]);

            return;
        }

        // Only forward the identifiers a tap needs — never the rendered strings,
        // which the device localises itself.
        $data = array_filter([
            'type' => isset($payload['order_id']) ? 'order' : (isset($payload['booking_id']) ? 'booking' : null),
            'order_id' => $payload['order_id'] ?? null,
            'booking_id' => $payload['booking_id'] ?? null,
            'store_token' => $payload['store_token'] ?? null,
        ], static fn ($v) => $v !== null);

        foreach ($devices as $device) {
            $result = $this->fcm->send($device->token, $title, $body, $data);

            if ($result === FcmResult::Unregistered) {
                $device->delete();
            }
        }
    }
}
