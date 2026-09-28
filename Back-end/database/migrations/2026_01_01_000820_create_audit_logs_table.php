<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Audit trail for important merchant actions (spec §35).
 *
 * Covers: price changes, booking status overrides, staff deactivation, booking
 * settings changes, QR regeneration, refunds, merchant approval/suspension.
 *
 * merchant_id is nullable because admin actions (approving a merchant) are
 * logged by an actor who belongs to no tenant.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('audit_logs', function (Blueprint $table) {
            $table->id();

            $table->foreignId('merchant_id')->nullable()->constrained('merchants')->nullOnDelete();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();

            $table->string('action', 60);
            $table->nullableMorphs('auditable');

            $table->json('old_values')->nullable();
            $table->json('new_values')->nullable();

            $table->char('ip_hash', 64)->nullable();
            $table->string('user_agent', 512)->nullable();

            $table->timestamp('created_at')->useCurrent();

            $table->index(['merchant_id', 'created_at']);
            $table->index(['action', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_logs');
    }
};
