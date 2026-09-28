<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * Delivery joins pickup/dine-in as a fulfilment type (feature expansion), and
 * curbside is reserved here so the next slice needs no enum change.
 *
 * A delivery order SNAPSHOTS the address it was sent to — the same discipline
 * as the price snapshot: editing or deleting the customer's saved address later
 * must never rewrite where a past order went. `delivery_fee` is server-set in
 * OrderService and added to the total.
 */
return new class extends Migration
{
    public function up(): void
    {
        DB::statement("ALTER TABLE `orders` MODIFY `fulfillment_type` "
            ."ENUM('pickup','dine_in','delivery','curbside') NOT NULL DEFAULT 'pickup'");

        Schema::table('orders', function (Blueprint $table): void {
            // Which saved address this went to (nullable: the snapshot below is
            // the source of truth, so a later address deletion is harmless).
            $table->foreignId('customer_address_id')->nullable()->after('customer_id')
                ->constrained('customer_addresses')->nullOnDelete();

            $table->decimal('delivery_fee', 10, 2)->default(0)->after('subtotal');

            // Snapshot of the destination, as sent.
            $table->string('delivery_address', 255)->nullable()->after('table_number');
            $table->string('delivery_details', 255)->nullable()->after('delivery_address');
            $table->decimal('delivery_latitude', 10, 8)->nullable()->after('delivery_details');
            $table->decimal('delivery_longitude', 11, 8)->nullable()->after('delivery_latitude');
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table): void {
            $table->dropConstrainedForeignId('customer_address_id');
            $table->dropColumn([
                'delivery_fee', 'delivery_address', 'delivery_details',
                'delivery_latitude', 'delivery_longitude',
            ]);
        });

        DB::statement("ALTER TABLE `orders` MODIFY `fulfillment_type` "
            ."ENUM('pickup','dine_in') NOT NULL DEFAULT 'pickup'");
    }
};
