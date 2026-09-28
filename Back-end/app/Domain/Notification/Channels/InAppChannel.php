<?php

namespace App\Domain\Notification\Channels;

use App\Domain\Notification\NotificationChannel;
use App\Models\User;

/**
 * The in-app inbox.
 *
 * Delivery is a no-op because the wasla_notifications row IS the message — the
 * app reads its inbox from that table. Kept as a channel so the inbox is part
 * of the same pipeline as everything else rather than a special case.
 */
class InAppChannel implements NotificationChannel
{
    public function key(): string
    {
        return 'in_app';
    }

    public function send(User $user, string $title, string $body, array $payload): void
    {
        // Intentionally empty — see the class docblock.
    }
}
