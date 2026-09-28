<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Push notification device registrations (spec §23).
 *
 * One user can have several devices. Tokens rotate, so `last_seen_at` lets a
 * cleanup job prune ones that have gone quiet rather than pushing into the void.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('device_tokens', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained('users')->cascadeOnDelete();

            $table->string('token', 512);
            $table->enum('platform', ['ios', 'android']);
            $table->string('app_version', 20)->nullable();
            $table->string('device_model')->nullable();
            $table->timestamp('last_seen_at')->nullable();

            $table->timestamps();

            $table->unique(['user_id', 'token'], 'device_tokens_user_token_unq');
            $table->index('user_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_tokens');
    }
};
