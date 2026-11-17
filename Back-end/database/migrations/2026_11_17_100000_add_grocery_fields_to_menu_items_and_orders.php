<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Grocery products on the shared catalogue tables, and how an order is paid.
 *
 *  - compare_at_price: the "was" price a discount badge is computed from.
 *  - unit: "1 كجم", "500 جم", "6 حبات" — printed beside the price.
 *  - stock_quantity: null = not tracked (restaurants); a number is decremented
 *    on every placed order and refuses the sale at zero.
 *  - orders.payment_method: pay_at_store (restaurants) | cash_on_delivery
 *    (supermarkets) | online (reserved). The engine decides; clients only read.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('menu_items', function (Blueprint $table): void {
            $table->decimal('compare_at_price', 8, 2)->nullable()->after('price');
            $table->string('unit', 40)->nullable()->after('compare_at_price');
            $table->integer('stock_quantity')->nullable()->after('unit');
        });

        Schema::table('orders', function (Blueprint $table): void {
            $table->string('payment_method', 20)->default('pay_at_store')->after('fulfillment_type');
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table): void {
            $table->dropColumn('payment_method');
        });

        Schema::table('menu_items', function (Blueprint $table): void {
            $table->dropColumn(['compare_at_price', 'unit', 'stock_quantity']);
        });
    }
};
