<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Per-staff working hours and breaks (ARCHITECTURE.md §5.2, spec §15).
 *
 * The availability engine intersects this with the branch schedule, then
 * subtracts the break (§6.1 step 3). Like branch_schedules, multiple rows per
 * day are allowed for split shifts.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff_schedules', function (Blueprint $table) {
            $table->id();
            $table->foreignId('staff_id')->constrained('staff')->cascadeOnDelete();

            $table->unsignedTinyInteger('day_of_week');
            $table->time('starts_at');
            $table->time('ends_at');

            $table->time('break_starts_at')->nullable();
            $table->time('break_ends_at')->nullable();

            $table->boolean('is_off')->default(false);

            $table->timestamps();

            $table->unique(['staff_id', 'day_of_week', 'starts_at']);
            $table->index(['staff_id', 'day_of_week']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_schedules');
    }
};
