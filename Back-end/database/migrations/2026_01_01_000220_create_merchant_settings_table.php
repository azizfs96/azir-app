<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Rare / advanced merchant options (ARCHITECTURE.md §5.2).
 *
 * JSON on purpose: adding an advanced setting must never require a migration.
 * Hot flags that the availability engine and storefront read on every request
 * live as real columns on `booking_settings` instead.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('merchant_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('merchant_id')->unique()->constrained('merchants')->cascadeOnDelete();
            $table->json('settings')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('merchant_settings');
    }
};
