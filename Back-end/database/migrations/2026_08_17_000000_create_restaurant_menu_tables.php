<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ============================================================================
 * THE RESTAURANT MENU (RestaurantEngine — spec §43/§44's "future vertical")
 *
 * Engine-owned tables: nothing in core references them, and no core table
 * changed to add them — exactly the promise BusinessEngine was built on.
 *
 * The shape is the Jahez/HungerStation menu model:
 *
 *   category  →  item  →  option GROUP     →  option
 *   البرجر       بيج تيستي   الحجم (إلزامي ١من١)    وسط  +٠
 *                           الإضافات (٠..٥)        جبن إضافي  +٣
 *
 * A group's min/max selections express every Jahez pattern with two integers:
 *   required single choice  = min 1, max 1   (size)
 *   optional multi choice   = min 0, max N   (extras)
 *   required multi choice   = min 1, max N   (pick 2 sauces)
 *
 * Options carry a PRICE DELTA, not a price: the item owns the base price and
 * the selection arithmetic happens server-side at order time (R1), never in
 * the client.
 *
 * Every row carries merchant_id for the BelongsToTenant scope — same three-layer
 * isolation as the beauty tables (ARCHITECTURE.md §4).
 * ============================================================================
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('menu_categories', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->string('name_ar', 120);
            $table->string('name_en', 120)->nullable();
            $table->unsignedInteger('sort_order')->default(0);
            $table->boolean('is_active')->default(true);
            $table->timestamps();

            $table->index(['store_id', 'is_active', 'sort_order']);
        });

        Schema::create('menu_items', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();

            // nullOnDelete: deleting a category must never delete the dishes in
            // it — they fall back to "uncategorised", same as services.
            $table->foreignId('menu_category_id')->nullable()
                ->constrained('menu_categories')->nullOnDelete();

            $table->string('name_ar', 120);
            $table->string('name_en', 120)->nullable();
            $table->string('description_ar', 1000)->nullable();
            $table->string('description_en', 1000)->nullable();
            $table->decimal('price', 8, 2);
            $table->unsignedInteger('calories')->nullable();
            $table->string('image_path')->nullable();

            /*
             * is_available is the Jahez "sold out" toggle — a live operational
             * switch flipped mid-service, distinct from is_active (menu
             * curation). Both must be true for a customer to order it.
             */
            $table->boolean('is_available')->default(true);
            $table->boolean('is_active')->default(true);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            // Order lines will snapshot name+price (R1), so hard delete is
            // safe — but soft delete keeps the dashboard's history readable.
            $table->softDeletes();

            $table->index(['store_id', 'is_active', 'sort_order']);
            $table->index(['menu_category_id', 'sort_order']);
        });

        Schema::create('menu_option_groups', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->foreignId('menu_item_id')->constrained('menu_items')->cascadeOnDelete();
            $table->string('name_ar', 120);
            $table->string('name_en', 120)->nullable();

            // min 0 = optional, min>=1 = required; max 1 = single choice.
            // The pair is validated at write time (min <= max, max >= 1).
            $table->unsignedTinyInteger('min_select')->default(0);
            $table->unsignedTinyInteger('max_select')->default(1);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index(['menu_item_id', 'sort_order']);
        });

        Schema::create('menu_options', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->foreignId('menu_option_group_id')
                ->constrained('menu_option_groups')->cascadeOnDelete();
            $table->string('name_ar', 120);
            $table->string('name_en', 120)->nullable();

            // Signed on purpose: "بدون جبن" can be -2.00 as easily as +3.00.
            $table->decimal('price_delta', 8, 2)->default(0);
            $table->boolean('is_available')->default(true);
            $table->unsignedInteger('sort_order')->default(0);
            $table->timestamps();

            $table->index(['menu_option_group_id', 'sort_order']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('menu_options');
        Schema::dropIfExists('menu_option_groups');
        Schema::dropIfExists('menu_items');
        Schema::dropIfExists('menu_categories');
    }
};
