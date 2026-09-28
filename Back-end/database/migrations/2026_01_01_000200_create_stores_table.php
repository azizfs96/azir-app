<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The customer-facing storefront (ARCHITECTURE.md §5.2, §8.2).
 *
 * `public_token` is the ONLY identifier ever exposed publicly — the thing behind
 * wasla.sa/s/8F72K. Internal ids never appear in a URL (§24).
 *
 * `business_type` selects the BusinessEngine at runtime (§2.1). Adding a vertical
 * later means a new engine key here, not a schema change.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('stores', function (Blueprint $table) {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();

            // Crockford-style base32, ambiguous characters removed. See TokenGenerator.
            $table->char('public_token', 8)->unique();

            // BusinessEngine key. Only 'beauty_wellness' is implemented in the MVP.
            $table->string('business_type', 40)->default('beauty_wellness');

            $table->string('name_ar');
            $table->string('name_en')->nullable();
            $table->text('description_ar')->nullable();
            $table->text('description_en')->nullable();

            $table->string('logo_path')->nullable();
            $table->string('cover_path')->nullable();
            $table->char('brand_color', 7)->default('#111111');

            $table->string('timezone', 40)->default('Asia/Riyadh');
            $table->char('currency', 3)->default('SAR');

            // Many Saudi salons serve one gender only (§12 risk 10).
            $table->enum('gender_policy', ['all', 'women_only', 'men_only'])->default('all');

            $table->string('phone', 20)->nullable();
            $table->string('instagram')->nullable();

            $table->boolean('is_published')->default(false);
            $table->timestamp('published_at')->nullable();

            $table->timestamps();
            $table->softDeletes();

            $table->index('merchant_id');
            $table->index(['is_published', 'business_type']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('stores');
    }
};
