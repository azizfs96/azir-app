<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * Placing an order is a real way a customer acquires a store (R3), so
 * 'order' joins the added_via vocabulary alongside qr / deep_link / booking.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE `customer_stores` MODIFY `added_via` "
            ."ENUM('qr','deep_link','booking','order') NOT NULL DEFAULT 'qr'");
    }

    public function down(): void
    {
        DB::statement("ALTER TABLE `customer_stores` MODIFY `added_via` "
            ."ENUM('qr','deep_link','booking') NOT NULL DEFAULT 'qr'");
    }
};
