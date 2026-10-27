<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Delivery orders get a driver and one more lifecycle step:
 *
 *   ready ───► out_for_delivery ───► completed
 *
 * plus the distance the fee was computed from (snapshotted so the fee stays
 * reproducible after a branch moves or the pricing changes).
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE `orders` MODIFY `status` "
            ."ENUM('placed','accepted','preparing','ready','out_for_delivery','completed','rejected','cancelled') NOT NULL DEFAULT 'placed'");

        Schema::table('orders', function (Blueprint $table): void {
            $table->foreignId('driver_id')->nullable()->after('customer_car_id')
                ->constrained('drivers')->nullOnDelete();
            $table->decimal('delivery_distance_km', 6, 2)->nullable()->after('delivery_longitude');
            $table->dateTime('assigned_at')->nullable()->after('ready_at');
            $table->dateTime('out_for_delivery_at')->nullable()->after('assigned_at');

            $table->index(['driver_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table): void {
            $table->dropIndex(['driver_id', 'status']);
            $table->dropConstrainedForeignId('driver_id');
            $table->dropColumn(['delivery_distance_km', 'assigned_at', 'out_for_delivery_at']);
        });

        DB::statement("ALTER TABLE `orders` MODIFY `status` "
            ."ENUM('placed','accepted','preparing','ready','completed','rejected','cancelled') NOT NULL DEFAULT 'placed'");
    }
};
