<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Commercial Registration (السجل التجاري) for the tax invoice header — the CR
 * number a Saudi simplified tax invoice prints beside the VAT number.
 * Snapshotted onto the order like the rest of the seller's details.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('booking_settings', function (Blueprint $table) {
            $table->string('commercial_registration', 20)->nullable()->after('national_address');
        });
        Schema::table('orders', function (Blueprint $table) {
            $table->string('commercial_registration', 20)->nullable()->after('national_address');
        });
    }

    public function down(): void
    {
        Schema::table('booking_settings', fn (Blueprint $t) => $t->dropColumn('commercial_registration'));
        Schema::table('orders', fn (Blueprint $t) => $t->dropColumn('commercial_registration'));
    }
};
