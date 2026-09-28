<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A curbside order records WHICH car to bring the food to — a nullable link to
 * the saved car plus a snapshot of its description as sent, so a later edit or
 * deletion of the car never rewrites the order.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('orders', function (Blueprint $table): void {
            $table->foreignId('customer_car_id')->nullable()->after('customer_address_id')
                ->constrained('customer_cars')->nullOnDelete();
            $table->string('car_description', 120)->nullable()->after('delivery_longitude');
        });
    }

    public function down(): void
    {
        Schema::table('orders', function (Blueprint $table): void {
            $table->dropConstrainedForeignId('customer_car_id');
            $table->dropColumn('car_description');
        });
    }
};
