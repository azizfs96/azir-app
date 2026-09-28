<?php

namespace App\Domain\Notification;

use App\Models\User;

/**
 * A delivery channel (spec §23).
 *
 * Push and in-app ship in the MVP. SMS and WhatsApp are one class each — the
 * booking engine never learns they exist.
 */
interface NotificationChannel
{
    /** push | email | sms | whatsapp | in_app */
    public function key(): string;

    /** @param array<string, mixed> $payload */
    public function send(User $user, string $title, string $body, array $payload): void;
}
