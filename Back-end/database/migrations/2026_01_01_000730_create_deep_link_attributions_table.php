<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Deferred deep linking — surviving the App Store round-trip (spec §7).
 *
 * "Do not lose the original merchant context after installation. This is
 * extremely important."
 *
 * Firebase Dynamic Links shut down in August 2025, so this is built in-house
 * (ARCHITECTURE.md §8.3):
 *
 *   1. Landing page records a device fingerprint + the store token here.
 *   2. User installs and opens the app.
 *   3. App posts its own fingerprint; a match within the TTL returns the token.
 *   4. App opens that merchant. Context preserved.
 *
 * Android does better than this via Play Install Referrer (exact, not
 * probabilistic). iOS relies on the fingerprint match, with a visible
 * "enter store code" fallback so a miss is never a dead end.
 *
 * Rows are short-lived by design: matching gets less reliable with age, and this
 * is fingerprint data we should not retain.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('deep_link_attributions', function (Blueprint $table) {
            $table->id();

            // Deliberately NOT a FK to stores: the row must survive even if the
            // token is later regenerated, and it is written pre-authentication.
            $table->char('store_public_token', 8);

            $table->char('fingerprint_hash', 64);
            $table->enum('platform', ['ios', 'android', 'web'])->nullable();
            $table->char('ip_hash', 64)->nullable();
            $table->string('user_agent', 512)->nullable();

            $table->foreignId('claimed_by_customer_id')->nullable()
                ->constrained('customers')->nullOnDelete();
            $table->timestamp('claimed_at')->nullable();

            $table->timestamp('expires_at');
            $table->timestamps();

            // The matching query: unclaimed + same fingerprint + not expired.
            $table->index(['fingerprint_hash', 'expires_at']);
            $table->index('expires_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('deep_link_attributions');
    }
};
