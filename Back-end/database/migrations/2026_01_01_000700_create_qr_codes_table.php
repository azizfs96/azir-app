<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The merchant's QR code (spec §24).
 *
 * The encoded URL is https://wasla.sa/s/{public_token} — never an internal id.
 * `version` increments if a merchant regenerates (e.g. printed sheets stolen);
 * old printed codes then resolve to a "this code was replaced" response rather
 * than silently failing.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('qr_codes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('merchant_id')->constrained('merchants')->cascadeOnDelete();
            $table->foreignId('store_id')->unique()->constrained('stores')->cascadeOnDelete();

            // Mirrors stores.public_token; kept here so a regenerated code has history.
            $table->char('public_token', 8);

            $table->string('image_path')->nullable();
            $table->unsignedBigInteger('scan_count')->default(0);
            $table->timestamp('last_scanned_at')->nullable();
            $table->unsignedSmallInteger('version')->default(1);
            $table->boolean('is_active')->default(true);

            $table->timestamps();

            $table->index('public_token');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('qr_codes');
    }
};
