<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The tenant root (ARCHITECTURE.md §4, §5.2).
 *
 * Every tenant-owned row in the system carries `merchant_id` and is filtered by
 * the BelongsToTenant global scope. A merchant is not visible to customers until
 * status = approved AND its store is published.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('merchants', function (Blueprint $table) {
            $table->id();

            // FK added after users gains merchant_id, to avoid a circular dependency.
            $table->foreignId('owner_user_id')->constrained('users')->cascadeOnDelete();

            $table->string('legal_name');
            $table->string('display_name');
            $table->string('commercial_registration', 30)->nullable();
            $table->string('vat_number', 30)->nullable();

            $table->string('contact_phone', 20);
            $table->string('contact_email')->nullable();

            $table->enum('status', ['pending', 'approved', 'suspended', 'rejected'])
                ->default('pending');

            // Resumable onboarding (§11) — which of the 9 steps is next.
            $table->unsignedTinyInteger('onboarding_step')->default(1);
            $table->timestamp('onboarded_at')->nullable();

            $table->timestamp('approved_at')->nullable();
            $table->foreignId('approved_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamp('suspended_at')->nullable();
            $table->string('suspension_reason')->nullable();

            $table->timestamps();
            $table->softDeletes();

            $table->index('status');
            $table->index('owner_user_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('merchants');
    }
};
