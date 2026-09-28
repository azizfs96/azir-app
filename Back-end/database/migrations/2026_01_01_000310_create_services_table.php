<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Bookable services (ARCHITECTURE.md §5.2, §14).
 *
 * Belongs to the Beauty & Wellness engine's catalog. A future Restaurant engine
 * would add its own `menu_items` table rather than overloading this one (§2).
 *
 * duration_minutes drives the availability engine; buffer_after_minutes is
 * per-service cleanup time added on top of the branch-level buffer (§6.1).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('services', function (Blueprint $table) {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->constrained('stores')->cascadeOnDelete();
            $table->foreignId('service_category_id')->nullable()
                ->constrained('service_categories')->nullOnDelete();

            $table->string('name_ar');
            $table->string('name_en')->nullable();
            $table->text('description_ar')->nullable();
            $table->text('description_en')->nullable();
            $table->string('image_path')->nullable();

            $table->decimal('price', 10, 2);
            $table->char('currency', 3)->default('SAR');
            $table->unsignedSmallInteger('duration_minutes');
            $table->unsignedSmallInteger('buffer_after_minutes')->default(0);

            $table->boolean('is_active')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(0);

            $table->timestamps();
            $table->softDeletes();

            $table->index(['store_id', 'is_active']);
            $table->index('service_category_id');
            $table->index('merchant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('services');
    }
};
