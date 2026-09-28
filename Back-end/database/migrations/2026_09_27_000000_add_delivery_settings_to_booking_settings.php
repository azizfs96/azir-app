<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Delivery & curbside are new restaurant fulfilment options (feature expansion).
 *
 * Each is a per-store toggle the merchant controls from the dashboard — the same
 * schema-driven Settings form that already renders order_pickup/order_dine_in
 * picks these up automatically (RestaurantEngine::configurationSchema).
 *
 * Both default OFF: an existing restaurant keeps offering exactly what it did
 * (pickup + dine-in) until the merchant opts in.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('booking_settings', function (Blueprint $table): void {
            $table->boolean('order_delivery')->default(false)->after('order_dine_in');
            $table->boolean('order_curbside')->default(false)->after('order_delivery');

            // Server-owned pricing: a flat delivery fee added to the order total,
            // and an optional minimum subtotal before delivery is allowed.
            $table->decimal('delivery_fee', 10, 2)->default(0)->after('order_curbside');
            $table->decimal('delivery_min_order', 10, 2)->nullable()->after('delivery_fee');
        });
    }

    public function down(): void
    {
        Schema::table('booking_settings', function (Blueprint $table): void {
            $table->dropColumn([
                'order_delivery', 'order_curbside', 'delivery_fee', 'delivery_min_order',
            ]);
        });
    }
};
