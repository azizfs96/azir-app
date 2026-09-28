<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Order lifecycle notifications (spec §23) reuse the same inbox as bookings.
 *
 * A notification links to EITHER a booking or an order, never both, so the app
 * can deep-link "طلبك جاهز" straight to the order it is about.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('wasla_notifications', function (Blueprint $table) {
            $table->foreignId('order_id')->nullable()->after('booking_id')
                ->constrained('orders')->cascadeOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('wasla_notifications', function (Blueprint $table) {
            $table->dropConstrainedForeignId('order_id');
        });
    }
};
