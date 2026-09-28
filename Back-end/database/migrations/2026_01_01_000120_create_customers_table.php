<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Customer profile (ARCHITECTURE.md §5.2).
 *
 * A customer belongs to the PLATFORM, not to a merchant — one identity across
 * every store they have ever scanned. The merchant's view of "their customers"
 * is derived from bookings and customer_stores, never from ownership here.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained('users')->cascadeOnDelete();

            $table->string('first_name')->nullable();
            $table->string('last_name')->nullable();

            // Relevant because many Saudi salons are women-only or men-only (§12 risk 10).
            $table->enum('gender', ['male', 'female'])->nullable();
            $table->date('date_of_birth')->nullable();

            $table->boolean('marketing_opt_in')->default(false);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('customers');
    }
};
