<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Notification log + in-app inbox (spec §23).
 *
 * Channel-agnostic: push and email ship in the MVP, SMS and WhatsApp are added
 * later by writing a driver, with no change to the booking engine that triggers
 * them (ARCHITECTURE.md §12 risk 12).
 *
 * `template_key` + `payload` rather than a rendered string, so the same record
 * renders in Arabic or English depending on who reads it (spec §33).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('wasla_notifications', function (Blueprint $table) {
            $table->id();

            $table->morphs('notifiable');

            $table->enum('channel', ['push', 'email', 'sms', 'whatsapp', 'in_app']);

            // e.g. booking.confirmed, booking.reminder, booking.cancelled
            $table->string('template_key', 60);
            $table->json('payload')->nullable();
            $table->enum('locale', ['ar', 'en'])->default('ar');

            $table->enum('status', ['queued', 'sent', 'failed', 'read'])->default('queued');
            $table->timestamp('sent_at')->nullable();
            $table->timestamp('read_at')->nullable();
            $table->string('provider_message_id')->nullable();
            $table->string('failure_reason')->nullable();

            $table->foreignId('booking_id')->nullable()->constrained('bookings')->cascadeOnDelete();

            $table->timestamps();

            $table->index(['status', 'channel']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('wasla_notifications');
    }
};
