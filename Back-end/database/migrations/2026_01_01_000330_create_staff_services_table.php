<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which staff can perform which services (spec §15).
 *
 * CRITICAL RULE, relied on by the availability engine (§6.1 step 2):
 *   A staff member with ZERO rows here can perform ALL active services.
 *   Only once they have at least one row does the list become restrictive.
 *
 * This keeps the common case ("everyone does everything") zero-setup, which is
 * the difference between a 5-minute onboarding and a 30-minute one.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff_services', function (Blueprint $table) {
            $table->id();
            $table->foreignId('staff_id')->constrained('staff')->cascadeOnDelete();
            $table->foreignId('service_id')->constrained('services')->cascadeOnDelete();

            // A senior stylist may be faster, or priced differently.
            $table->unsignedSmallInteger('duration_override_minutes')->nullable();
            $table->decimal('price_override', 10, 2)->nullable();

            $table->timestamps();

            $table->unique(['staff_id', 'service_id']);
            $table->index('service_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_services');
    }
};
