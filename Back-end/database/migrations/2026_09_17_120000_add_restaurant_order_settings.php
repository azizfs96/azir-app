<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Restaurant order settings live on the store's existing settings row (R3).
 *
 * booking_settings is already the per-store configuration record every engine
 * reads; the RestaurantEngine declared these keys in its configurationSchema,
 * and this gives them a home so a merchant can actually toggle auto-accept and
 * set a default prep time. Defaults match RestaurantEngine::defaultConfiguration.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('booking_settings', function (Blueprint $table): void {
            $table->boolean('order_pickup')->default(true)->after('guest_booking');
            $table->boolean('order_dine_in')->default(true)->after('order_pickup');
            $table->boolean('auto_accept_orders')->default(false)->after('order_dine_in');
            $table->unsignedInteger('default_prep_minutes')->default(20)->after('auto_accept_orders');
        });
    }

    public function down(): void
    {
        Schema::table('booking_settings', function (Blueprint $table): void {
            $table->dropColumn(['order_pickup', 'order_dine_in', 'auto_accept_orders', 'default_prep_minutes']);
        });
    }
};
