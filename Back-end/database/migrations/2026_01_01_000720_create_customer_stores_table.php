<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * "My Stores" — the entire discovery model (spec §5, §46).
 *
 * ============================================================================
 * THIS TABLE IS THE PRODUCT RULE MADE PHYSICAL.
 *
 * The customer home screen is exactly:
 *     SELECT ... FROM customer_stores WHERE customer_id = ?
 *
 * A row appears here ONLY when the customer personally scanned a QR or opened
 * a deep link. There is no query anywhere in this system that returns stores a
 * customer has not added. Wasla is not a marketplace, and the absence of a
 * discovery path is enforced by there being no table to discover from.
 * ============================================================================
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customer_stores', function (Blueprint $table) {
            $table->id();
            $table->foreignId('customer_id')->constrained('customers')->cascadeOnDelete();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();

            // How this store entered the customer's list. Never 'search'.
            $table->enum('added_via', ['qr', 'deep_link', 'booking'])->default('qr');

            $table->timestamp('first_added_at')->useCurrent();
            $table->timestamp('last_visited_at')->nullable();
            $table->timestamp('last_booking_at')->nullable();

            // Customer can remove a store from their list without losing history.
            $table->boolean('is_hidden')->default(false);

            $table->timestamps();

            $table->unique(['customer_id', 'store_id']);
            // Drives the home screen ordering: most recently used first.
            $table->index(['customer_id', 'last_visited_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('customer_stores');
    }
};
