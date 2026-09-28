<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Payment attempts and refunds (spec §20; ARCHITECTURE.md §5.2).
 *
 * Provider-agnostic by design: `provider` + `provider_payment_id` + `raw_response`
 * mean swapping Moyasar for Tap touches the provider class only, never this
 * table or the booking engine.
 *
 * `idempotency_key` is unique — a retried charge request can never double-charge.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('booking_id')->constrained('bookings')->cascadeOnDelete();

            $table->string('provider', 40)->default('manual');
            $table->string('provider_payment_id')->nullable();

            $table->enum('type', ['full', 'deposit', 'balance', 'refund'])->default('full');
            $table->decimal('amount', 10, 2);
            $table->char('currency', 3)->default('SAR');

            $table->enum('status', ['pending', 'authorized', 'captured', 'failed', 'refunded'])
                ->default('pending');

            // mada is the dominant Saudi debit network — it is not "just Visa".
            $table->enum('method', ['mada', 'visa', 'mastercard', 'apple_pay', 'cash'])->nullable();

            $table->string('failure_reason')->nullable();
            $table->json('raw_response')->nullable();

            $table->string('idempotency_key', 64)->unique();

            $table->timestamp('paid_at')->nullable();
            $table->timestamp('refunded_at')->nullable();
            $table->foreignId('refund_of_payment_id')->nullable()
                ->constrained('payments')->nullOnDelete();

            $table->timestamps();

            $table->index('booking_id');
            $table->index(['provider', 'provider_payment_id']);
            $table->index(['merchant_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payments');
    }
};
