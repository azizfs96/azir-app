<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Ad-hoc closures that override the weekly schedule (ARCHITECTURE.md §5.2).
 *
 * Serves both levels: a staff holiday (staff_id set) or a whole-branch closure
 * such as Eid or National Day (branch_id set). Exactly one of the two is set;
 * this is enforced in the model, since MySQL has no CHECK-with-XOR portability
 * guarantee worth relying on.
 *
 * Stored as full DATETIME in UTC so a closure can span days and part-days alike.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('time_off', function (Blueprint $table) {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('staff_id')->nullable()->constrained('staff')->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained('branches')->cascadeOnDelete();

            $table->dateTime('starts_at');
            $table->dateTime('ends_at');
            $table->string('reason')->nullable();

            // Eid / National Day repeat every year.
            $table->boolean('is_recurring_annual')->default(false);

            $table->timestamps();

            $table->index(['staff_id', 'starts_at', 'ends_at']);
            $table->index(['branch_id', 'starts_at', 'ends_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('time_off');
    }
};
