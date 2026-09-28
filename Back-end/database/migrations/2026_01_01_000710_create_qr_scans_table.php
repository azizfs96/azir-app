<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * QR scan analytics (spec §25).
 *
 * customer_id is nullable because the most valuable scan of all — a brand new
 * customer's first ever scan — happens BEFORE they authenticate.
 *
 * Privacy: the IP is stored hashed, never raw. Analytics needs "was this the
 * same visitor", not "who lives at this address".
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('qr_scans', function (Blueprint $table) {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->foreignId('customer_id')->nullable()->constrained('customers')->nullOnDelete();

            // Ties pre-auth and post-auth scans from the same device together.
            $table->char('session_id', 36)->nullable();
            $table->char('ip_hash', 64)->nullable();
            $table->string('user_agent', 512)->nullable();
            $table->enum('platform', ['ios', 'android', 'web'])->nullable();

            $table->boolean('is_first_scan_for_customer')->default(false);

            // Closes the funnel: scan -> store open -> booking (spec §25).
            $table->foreignId('resulted_in_booking_id')->nullable()
                ->constrained('bookings')->nullOnDelete();

            $table->timestamp('scanned_at')->useCurrent();

            $table->index(['store_id', 'scanned_at']);
            $table->index(['merchant_id', 'scanned_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('qr_scans');
    }
};
