<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Delivery drivers — created by the merchant from the dashboard, signing in to
 * the driver app with phone + password. A driver is a tenant-owned row (the
 * merchant's) backed by a `users` login with role `driver`.
 *
 * The driver's phone lives HERE (unique across drivers) and not on `users`:
 * `users.phone` is the customer identity, and the same person may well be a
 * customer of the platform too. The user row gets a synthetic email instead.
 *
 * Live position is kept as four columns on the driver (one row per driver,
 * updated in place) rather than a growing location log — tracking reads are
 * a single indexed lookup and the table never grows with traffic.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE `users` MODIFY `role` ENUM('customer','merchant_owner','merchant_staff','admin','driver') NOT NULL DEFAULT 'customer'");

        Schema::create('drivers', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('merchant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('store_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('name', 120);
            $table->string('phone', 20)->unique();   // E.164; the driver's login id
            $table->string('vehicle', 80)->nullable(); // "تويوتا كامري أبيض · أ ب ج 1234"
            $table->boolean('is_active')->default(true);

            // Last known position (driver app sends it while delivering).
            $table->decimal('last_latitude', 10, 8)->nullable();
            $table->decimal('last_longitude', 11, 8)->nullable();
            $table->unsignedSmallInteger('last_heading')->nullable();
            $table->decimal('last_speed_kmh', 6, 2)->nullable();
            $table->timestamp('last_located_at')->nullable();

            $table->timestamps();

            $table->index(['store_id', 'is_active']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('drivers');
        DB::statement("ALTER TABLE `users` MODIFY `role` ENUM('customer','merchant_owner','merchant_staff','admin') NOT NULL DEFAULT 'customer'");
    }
};
