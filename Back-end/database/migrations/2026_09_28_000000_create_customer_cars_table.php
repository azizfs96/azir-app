<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ============================================================================
 * CUSTOMER CARS (feature expansion — curbside "من السيارة")
 *
 * A car belongs to the PLATFORM customer, not to any store — the same central
 * model as addresses. A curbside order pulls the chosen car and SNAPSHOTS its
 * description onto the order, so editing/deleting the car never rewrites a past
 * order. Deliberately NOT tenant-scoped.
 * ============================================================================
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customer_cars', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('customer_id')->constrained('customers')->cascadeOnDelete();

            $table->string('brand', 40);       // e.g. تويوتا
            $table->string('color', 30);       // e.g. أبيض
            $table->string('plate_letters', 12); // e.g. أ ب ج
            $table->string('plate_numbers', 8);  // e.g. 4592

            $table->boolean('is_default')->default(false);
            $table->timestamps();

            $table->index(['customer_id', 'is_default']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('customer_cars');
    }
};
