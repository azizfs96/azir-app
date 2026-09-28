<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Bookings (spec §18, §19; ARCHITECTURE.md §5.2).
 *
 * NULLABILITY MATTERS HERE:
 *   staff_id    — null when the merchant exposes no staff selection AND has no
 *                 staff at all; the branch is the resource (spec §18).
 *   branch_id   — null only in degenerate data; normally always resolved.
 *   customer_id — null for guest bookings (guest_name/guest_phone carry it).
 *
 * Timestamps are UTC; the store's timezone renders them (§5.4).
 * Prices are snapshotted at booking time so a later price change never rewrites
 * history.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('bookings', function (Blueprint $table) {
            $table->id();

            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained('branches')->nullOnDelete();
            $table->foreignId('customer_id')->nullable()->constrained('customers')->nullOnDelete();
            $table->foreignId('service_id')->constrained('services')->restrictOnDelete();
            $table->foreignId('staff_id')->nullable()->constrained('staff')->nullOnDelete();

            // Guest booking (spec §10 guest_booking).
            $table->string('guest_name')->nullable();
            $table->string('guest_phone', 20)->nullable();

            // Human-readable, spoken over the phone. e.g. WSL-4K7QX2
            $table->string('reference', 12)->unique();

            $table->dateTime('starts_at');
            $table->dateTime('ends_at');
            $table->unsignedSmallInteger('duration_minutes');

            // Snapshot of price at time of booking.
            $table->decimal('price', 10, 2);
            $table->decimal('deposit_amount', 10, 2)->default(0);
            $table->decimal('paid_amount', 10, 2)->default(0);
            $table->char('currency', 3)->default('SAR');

            // State machine — transitions validated in the model (§5.3).
            $table->enum('booking_status', [
                'pending', 'confirmed', 'checked_in', 'completed', 'cancelled', 'no_show',
            ])->default('pending');

            $table->enum('payment_status', [
                'unpaid', 'deposit_paid', 'paid', 'refunded', 'partially_refunded', 'failed',
            ])->default('unpaid');

            $table->text('customer_notes')->nullable();
            $table->text('merchant_notes')->nullable();

            // Attribution for QR analytics (spec §25).
            $table->enum('source', ['qr', 'app', 'dashboard'])->default('app');

            $table->enum('cancelled_by', ['customer', 'merchant', 'system'])->nullable();
            $table->timestamp('cancelled_at')->nullable();
            $table->string('cancellation_reason')->nullable();

            $table->foreignId('rescheduled_from_booking_id')->nullable()
                ->constrained('bookings')->nullOnDelete();

            $table->timestamp('checked_in_at')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamp('reminder_sent_at')->nullable();

            $table->json('metadata')->nullable();

            $table->timestamps();
            $table->softDeletes();

            // ---- Indexes, tuned per spec §28 ----

            // Hottest path: the availability engine's staff conflict scan (§6.1 step 3).
            $table->index(['staff_id', 'starts_at', 'ends_at'], 'bookings_staff_window_idx');

            // Availability when the branch itself is the resource.
            $table->index(['branch_id', 'starts_at'], 'bookings_branch_start_idx');

            // Merchant dashboard: today / upcoming / by status (spec §13).
            $table->index(['store_id', 'booking_status', 'starts_at'], 'bookings_store_status_idx');

            // Reports and revenue rollups.
            $table->index(['merchant_id', 'starts_at'], 'bookings_merchant_start_idx');

            // Customer "my bookings", newest first.
            $table->index(['customer_id', 'starts_at'], 'bookings_customer_start_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('bookings');
    }
};
