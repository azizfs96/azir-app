<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ============================================================================
 * RESTAURANT ORDERS (RestaurantEngine, R3) — the analogue of bookings.
 *
 * A booking reserves a slot; an order buys a basket of dishes. Same platform
 * spine (merchant/store/customer, a reference, a state machine, events), a
 * different fulfilment.
 *
 * PRICE IS SNAPSHOTTED, exactly like bookings snapshot the service price: an
 * order line records the dish name and unit price AS SOLD, and each chosen
 * option records its name and delta AS SOLD. Editing or deleting a menu item
 * afterwards must never rewrite a past order — so the menu FKs null on delete
 * and history reads from the snapshot columns, never the live menu.
 *
 * Money is computed and stored by the server (OrderService); the client's
 * figure is display-only and never persisted.
 * ============================================================================
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('orders', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->foreignId('branch_id')->nullable()->constrained('branches')->nullOnDelete();
            $table->foreignId('customer_id')->nullable()->constrained('customers')->nullOnDelete();

            $table->string('reference', 20)->unique();

            $table->enum('status', [
                'placed', 'accepted', 'preparing', 'ready', 'completed', 'rejected', 'cancelled',
            ])->default('placed');

            // How the customer takes the order. Delivery is a later, larger
            // feature (addresses, zones, drivers) — deliberately absent.
            $table->enum('fulfillment_type', ['pickup', 'dine_in'])->default('pickup');

            // Dine-in orders may carry a table number; pickup leaves it null.
            $table->string('table_number', 20)->nullable();

            $table->decimal('subtotal', 10, 2)->default(0);
            $table->decimal('total', 10, 2)->default(0);

            // Committed when the restaurant accepts (or auto-accept fills it
            // from the engine's default_prep_minutes).
            $table->unsignedInteger('prep_minutes')->nullable();

            $table->string('customer_notes', 500)->nullable();
            $table->string('rejection_reason', 255)->nullable();
            $table->enum('cancelled_by', ['customer', 'merchant', 'system'])->nullable();

            // Denormalised lifecycle timestamps for the dashboard.
            $table->dateTime('accepted_at')->nullable();
            $table->dateTime('ready_at')->nullable();
            $table->dateTime('completed_at')->nullable();
            $table->dateTime('cancelled_at')->nullable();

            $table->string('source', 20)->default('app');
            $table->timestamps();

            $table->index(['store_id', 'status', 'created_at']);
            $table->index(['customer_id', 'created_at']);
        });

        Schema::create('order_items', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('order_id')->constrained('orders')->cascadeOnDelete();
            // Null on delete: the snapshot columns keep history readable even
            // after the dish is removed from the menu.
            $table->foreignId('menu_item_id')->nullable()->constrained('menu_items')->nullOnDelete();

            $table->string('name', 120);        // snapshot
            $table->decimal('unit_price', 10, 2); // base + option deltas, as sold
            $table->unsignedInteger('quantity');
            $table->decimal('line_total', 10, 2);
            $table->timestamps();

            $table->index('order_id');
        });

        Schema::create('order_item_options', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('order_item_id')->constrained('order_items')->cascadeOnDelete();
            $table->foreignId('menu_option_id')->nullable()->constrained('menu_options')->nullOnDelete();

            $table->string('group_name', 120); // snapshot
            $table->string('name', 120);        // snapshot
            $table->decimal('price_delta', 10, 2)->default(0);
            $table->timestamps();

            $table->index('order_item_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('order_item_options');
        Schema::dropIfExists('order_items');
        Schema::dropIfExists('orders');
    }
};
