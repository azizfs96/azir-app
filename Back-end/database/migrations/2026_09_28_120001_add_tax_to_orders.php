<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The tax an order actually charged, snapshotted at placement.
 *
 * Like the delivery address, the seller's VAT details are copied onto the order
 * so a later settings change never rewrites an invoice already issued — a tax
 * document must reflect the terms in force when it was created.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->decimal('tax_rate', 5, 2)->default(0)->after('delivery_fee');
            $table->decimal('tax_amount', 10, 2)->default(0)->after('tax_rate');
            $table->string('seller_name')->nullable()->after('tax_amount');
            $table->string('tax_number', 20)->nullable()->after('seller_name');
            $table->string('national_address')->nullable()->after('tax_number');
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table) {
            $table->dropColumn(['tax_rate', 'tax_amount', 'seller_name', 'tax_number', 'national_address']);
        });
    }
};
