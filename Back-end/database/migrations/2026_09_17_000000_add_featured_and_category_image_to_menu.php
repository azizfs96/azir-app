<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * ============================================================================
 * TWO MENU-MERCHANDISING FIELDS (agreed R1 improvements)
 *
 *   menu_items.is_featured   — "الأكثر طلباً": a curated strip at the top of
 *                              the menu, the way Jahez/HungerStation surface a
 *                              restaurant's hero dishes. A flag, not a computed
 *                              popularity score — the merchant decides.
 *
 *   menu_categories.image_path — an icon/photo per section (البرجر، المشروبات),
 *                              so the menu reads as a board of sections rather
 *                              than a bare text list.
 *
 * Both nullable/defaulted, so every existing menu keeps working untouched.
 * ============================================================================
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('menu_items', function (Blueprint $table): void {
            // Indexed with the store: the "featured" strip is a hot per-store
            // read, and the flag is highly selective.
            $table->boolean('is_featured')->default(false)->after('is_active');
            $table->index(['store_id', 'is_featured']);
        });

        Schema::table('menu_categories', function (Blueprint $table): void {
            $table->string('image_path')->nullable()->after('name_en');
        });
    }

    public function down(): void
    {
        Schema::table('menu_items', function (Blueprint $table): void {
            $table->dropIndex(['store_id', 'is_featured']);
            $table->dropColumn('is_featured');
        });

        Schema::table('menu_categories', function (Blueprint $table): void {
            $table->dropColumn('image_path');
        });
    }
};
