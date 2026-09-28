<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * VAT / e-invoicing settings (ZATCA Phase 1, "simplified tax invoice").
 *
 * All optional and per-store: a merchant who is not VAT-registered leaves
 * tax_enabled off and nothing about invoices changes. When on, the order total
 * carries 15% (configurable) and the invoice shows the VAT number, the National
 * Address and a ZATCA-compliant QR.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('booking_settings', function (Blueprint $table) {
            $table->boolean('tax_enabled')->default(false)->after('delivery_min_order');
            $table->decimal('tax_rate', 5, 2)->default(15)->after('tax_enabled');
            $table->string('tax_number', 20)->nullable()->after('tax_rate');       // VAT reg. no. (15 digits)
            $table->string('legal_name')->nullable()->after('tax_number');          // seller name on the invoice
            $table->string('national_address')->nullable()->after('legal_name');    // العنوان الوطني
        });
    }

    public function down(): void
    {
        Schema::table('booking_settings', function (Blueprint $table) {
            $table->dropColumn(['tax_enabled', 'tax_rate', 'tax_number', 'legal_name', 'national_address']);
        });
    }
};
