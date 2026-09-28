<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Staff are OPTIONAL (ARCHITECTURE.md §5.2, spec §15).
 *
 * A merchant can run with zero staff — the branch itself becomes the bookable
 * resource. When staff exist but `staff_selection` is off, the customer never
 * sees them and StaffAssigner picks one at booking time (§6.4).
 *
 * `user_id` is nullable: a staff member only needs a login if they use the
 * dashboard. Most do not.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('staff', function (Blueprint $table) {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained('branches')->nullOnDelete();
            $table->foreignId('user_id')->nullable()->constrained('users')->nullOnDelete();

            $table->string('name');
            $table->string('title_ar')->nullable();
            $table->string('title_en')->nullable();
            $table->string('avatar_path')->nullable();
            $table->enum('gender', ['male', 'female'])->nullable();
            $table->text('bio')->nullable();

            $table->boolean('is_active')->default(true);
            // Inactive-but-visible vs. active-but-not-bookable are different states.
            $table->boolean('is_bookable')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(0);

            $table->timestamps();
            $table->softDeletes();

            $table->index(['branch_id', 'is_active', 'is_bookable']);
            $table->index(['store_id', 'is_active']);
            $table->index('merchant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff');
    }
};
