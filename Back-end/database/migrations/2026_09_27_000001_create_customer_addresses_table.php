<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ============================================================================
 * CENTRAL CUSTOMER ADDRESSES (feature expansion — delivery)
 *
 * An address belongs to the PLATFORM customer, not to any store — the same
 * "one identity across every merchant" rule the Customer model already lives by
 * (ARCHITECTURE.md §5.2). The customer manages their addresses once, in the app,
 * and a store pulls the chosen one at checkout rather than asking again.
 *
 * Deliberately NOT tenant-scoped: a merchant must never read another store's
 * customers' addresses. Delivery orders SNAPSHOT the address they were sent to
 * (on the order row), so editing or deleting an address never rewrites history.
 * ============================================================================
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('customer_addresses', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('customer_id')->constrained('customers')->cascadeOnDelete();

            // A short label so the customer can tell their addresses apart.
            $table->enum('label', ['home', 'work', 'other'])->default('home');

            // Free-text address the customer typed or the map reverse-geocoded,
            // plus optional building/floor/landmark details.
            $table->string('address_text', 255);
            $table->string('details', 255)->nullable();

            // The pin the merchant delivers to.
            $table->decimal('latitude', 10, 8)->nullable();
            $table->decimal('longitude', 11, 8)->nullable();

            // Exactly one default per customer (enforced in the model, not the DB,
            // to keep the write a single cheap UPDATE).
            $table->boolean('is_default')->default(false);

            $table->timestamps();

            $table->index(['customer_id', 'is_default']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('customer_addresses');
    }
};
