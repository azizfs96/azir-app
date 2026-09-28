<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * THE configurable booking engine (spec §9, §10, §21, §22).
 *
 * These columns are what make the customer app adapt per merchant without any
 * merchant-specific code. The BeautyWellnessEngine reads this row and emits the
 * ordered step list that Flutter walks (ARCHITECTURE.md §2.2).
 *
 * Deliberately real columns rather than JSON: this row is read on EVERY store
 * open and every availability query, and several fields are filtered on.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('booking_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->unique()->constrained('stores')->cascadeOnDelete();

            // ---- The spec §10 toggles ----
            $table->boolean('staff_selection')->default(false);
            $table->boolean('branch_selection')->default(false);
            $table->boolean('payment_required')->default(false);
            $table->boolean('deposit_required')->default(false);
            $table->boolean('customer_notes')->default(true);
            $table->boolean('guest_booking')->default(false);
            $table->boolean('allow_cancellation')->default(true);
            $table->boolean('allow_rescheduling')->default(true);

            // ---- Deposit policy ----
            $table->enum('deposit_type', ['percent', 'fixed'])->default('percent');
            $table->decimal('deposit_value', 10, 2)->default(25.00);

            // ---- Cancellation policy (§21) ----
            // The customer sees this rendered as plain text BEFORE confirming.
            $table->unsignedSmallInteger('cancellation_deadline_hours')->default(4);
            $table->enum('refund_policy', ['full', 'deposit_forfeited', 'none'])
                ->default('deposit_forfeited');

            // ---- Rescheduling policy (§22) ----
            $table->unsignedSmallInteger('reschedule_deadline_hours')->default(4);

            // ---- Scheduling window ----
            $table->boolean('auto_confirm')->default(true);
            $table->unsignedSmallInteger('min_lead_time_minutes')->default(60);
            $table->unsignedSmallInteger('max_advance_days')->default(60);
            $table->unsignedSmallInteger('reminder_hours_before')->default(24);

            $table->timestamps();

            $table->index('merchant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('booking_settings');
    }
};
