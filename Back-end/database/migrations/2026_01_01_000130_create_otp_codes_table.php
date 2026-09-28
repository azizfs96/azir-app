<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * One-time passcodes for phone login (ARCHITECTURE.md §5.2, §34).
 *
 * The code is stored HASHED — a database read must never reveal a live code.
 * Attempts are counted so a code can be burned after N failures (§7.6).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('otp_codes', function (Blueprint $table) {
            $table->id();
            $table->string('phone', 20);
            $table->string('code_hash');
            $table->enum('purpose', ['login', 'verify_phone', 'merchant_login'])->default('login');
            $table->unsignedTinyInteger('attempts')->default(0);
            $table->string('ip_hash', 64)->nullable();
            $table->timestamp('expires_at');
            $table->timestamp('consumed_at')->nullable();
            $table->timestamps();

            $table->index(['phone', 'purpose', 'expires_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('otp_codes');
    }
};
