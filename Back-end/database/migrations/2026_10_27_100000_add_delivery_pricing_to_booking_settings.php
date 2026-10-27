<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Distance-based delivery pricing, decided by the merchant:
 *
 *   fixed   → `delivery_fee` (unchanged behaviour)
 *   per_km  → `delivery_base_fee` + `delivery_fee_per_km` × km
 *   tiers   → `delivery_tiers` = [{up_to_km, fee}, …], first matching tier wins
 *
 * `delivery_max_distance_km` (any mode) refuses orders beyond it BEFORE they are
 * placed. Distance is the straight line between the branch and the customer's
 * pin × `delivery_road_factor` (≈ road distance without a paid routing API).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('booking_settings', function (Blueprint $table): void {
            $table->string('delivery_pricing_mode', 16)->default('fixed')->after('delivery_fee');
            $table->decimal('delivery_base_fee', 10, 2)->default(0)->after('delivery_pricing_mode');
            $table->decimal('delivery_fee_per_km', 10, 2)->default(0)->after('delivery_base_fee');
            $table->json('delivery_tiers')->nullable()->after('delivery_fee_per_km');
            $table->decimal('delivery_max_distance_km', 6, 2)->nullable()->after('delivery_tiers');
            $table->decimal('delivery_road_factor', 4, 2)->default(1.30)->after('delivery_max_distance_km');
        });
    }

    public function down(): void
    {
        Schema::table('booking_settings', function (Blueprint $table): void {
            $table->dropColumn([
                'delivery_pricing_mode', 'delivery_base_fee', 'delivery_fee_per_km',
                'delivery_tiers', 'delivery_max_distance_km', 'delivery_road_factor',
            ]);
        });
    }
};
