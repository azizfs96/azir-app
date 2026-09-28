<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Physical locations (ARCHITECTURE.md §5.2, §16).
 *
 * If a store has exactly one active branch the customer is NEVER asked to choose
 * one — the availability engine resolves it silently (§6.1 step 1).
 *
 * lat/lng exist only to show the customer where to go after booking. There is no
 * proximity search anywhere in this system (§46).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('branches', function (Blueprint $table) {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();

            $table->string('name_ar');
            $table->string('name_en')->nullable();
            $table->string('address_line')->nullable();
            $table->string('city')->nullable();
            $table->decimal('latitude', 10, 8)->nullable();
            $table->decimal('longitude', 11, 8)->nullable();
            $table->string('phone', 20)->nullable();
            $table->string('google_maps_url')->nullable();

            // Turnaround padding applied around every booking by the availability engine.
            $table->unsignedSmallInteger('buffer_before_minutes')->default(0);
            $table->unsignedSmallInteger('buffer_after_minutes')->default(0);

            // The grid candidate start times are generated on (§6.1 step 4).
            $table->unsignedSmallInteger('slot_interval_minutes')->default(15);

            $table->boolean('is_active')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(0);

            $table->timestamps();
            $table->softDeletes();

            $table->index(['store_id', 'is_active']);
            $table->index('merchant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('branches');
    }
};
