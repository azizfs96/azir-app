<?php

namespace App\Models;

use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\MorphTo;

/**
 * A notification record and the in-app inbox (spec §23).
 *
 * Named WaslaNotification rather than Notification to avoid colliding with
 * Laravel's own notification system, which this deliberately does not use —
 * the platform needs one uniform log across push, SMS and WhatsApp, and a
 * template_key + payload shape that renders per reader's locale (§33).
 */
#[Fillable(['status', 'read_at'])]
class WaslaNotification extends Model
{
    protected $table = 'wasla_notifications';

    protected function casts(): array
    {
        return [
            'payload' => 'array',
            'sent_at' => 'immutable_datetime',
            'read_at' => 'immutable_datetime',
        ];
    }

    public function notifiable(): MorphTo
    {
        return $this->morphTo();
    }

    public function booking(): BelongsTo
    {
        return $this->belongsTo(Booking::class);
    }

    /**
     * The rendered title/body for whoever is reading it right now.
     *
     * Rendering happens at READ time, not send time, so a customer who switches
     * the app to English sees their history in English (§33).
     *
     * @return array{title: string, body: string}
     */
    public function render(?string $locale = null): array
    {
        $locale ??= $this->locale ?: 'ar';
        $payload = $this->payload ?? [];

        return [
            'title' => __("notifications.{$this->template_key}.title", $payload, $locale),
            'body' => __("notifications.{$this->template_key}.body", $payload, $locale),
        ];
    }

    public function markRead(): void
    {
        if ($this->read_at !== null) {
            return;
        }

        $this->forceFill([
            'status' => 'read',
            'read_at' => CarbonImmutable::now(),
        ])->save();
    }

    /** The app's inbox: in-app messages only, newest first. */
    /** @param  Builder<WaslaNotification>  $query */
    public function scopeInbox(Builder $query): Builder
    {
        return $query->where('channel', 'in_app')->latest('id');
    }

    /** @param  Builder<WaslaNotification>  $query */
    public function scopeUnread(Builder $query): Builder
    {
        return $query->whereNull('read_at');
    }
}
