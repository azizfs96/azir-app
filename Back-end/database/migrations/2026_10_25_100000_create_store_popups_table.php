<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Pop-up ads a merchant shows to customers who open THEIR store in the app —
 * a full-screen image (with an optional title) that appears on entry, the way
 * a standalone brand app announces an offer. Scheduled, ordered, and shown
 * according to a per-popup frequency so it never nags.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('store_popups', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('merchant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('store_id')->constrained()->cascadeOnDelete();
            $table->string('image_path')->nullable();
            $table->string('title_ar', 120)->nullable();
            $table->string('title_en', 120)->nullable();
            // every_visit | once_per_day | once — how often ONE customer sees it.
            $table->string('frequency', 20)->default('once_per_day');
            $table->timestamp('starts_at')->nullable();
            $table->timestamp('ends_at')->nullable();
            $table->boolean('is_active')->default(true);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index(['store_id', 'is_active', 'sort_order']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('store_popups');
    }
};
