<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Branch opening hours (ARCHITECTURE.md §5.2).
 *
 * MULTIPLE ROWS PER DAY ARE ALLOWED, and this is deliberate (§12 risk 9):
 * Saudi salons routinely close for prayer and reopen — e.g. 10:00-15:00 and
 * 16:00-23:00 on the same day. Modelling a day as a single open/close pair
 * would make split shifts impossible to retrofit later without a painful
 * migration, so it is supported from day one.
 *
 * Times are stored in the STORE's local timezone (§5.4).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('branch_schedules', function (Blueprint $table) {
            $table->id();
            $table->foreignId('branch_id')->constrained('branches')->cascadeOnDelete();

            // 0 = Sunday .. 6 = Saturday (the Saudi week starts Sunday).
            $table->unsignedTinyInteger('day_of_week');
            $table->time('opens_at');
            $table->time('closes_at');
            $table->boolean('is_closed')->default(false);

            $table->timestamps();

            $table->unique(['branch_id', 'day_of_week', 'opens_at']);
            $table->index(['branch_id', 'day_of_week']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('branch_schedules');
    }
};
