<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Single role-discriminated users table (ARCHITECTURE.md §5.2).
 *
 * Customers authenticate by phone + OTP and have no password. Merchant and
 * admin users authenticate by email + password. `merchant_id` is added in a
 * later migration because `merchants` does not exist yet at this point.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('name');

            // Customers may have no email; merchants/admins may have no phone.
            $table->string('email')->nullable()->unique();
            $table->timestamp('email_verified_at')->nullable();

            // E.164, e.g. +966501234567
            $table->string('phone', 20)->nullable()->unique();
            $table->timestamp('phone_verified_at')->nullable();

            // Nullable: OTP-only customers never set one.
            $table->string('password')->nullable();

            $table->enum('role', ['customer', 'merchant_owner', 'merchant_staff', 'admin'])
                ->default('customer');

            $table->enum('locale', ['ar', 'en'])->default('ar');
            $table->boolean('is_active')->default(true);
            $table->timestamp('last_login_at')->nullable();

            $table->rememberToken();
            $table->timestamps();

            $table->index('role');
        });

        Schema::create('password_reset_tokens', function (Blueprint $table) {
            $table->string('email')->primary();
            $table->string('token');
            $table->timestamp('created_at')->nullable();
        });

        Schema::create('sessions', function (Blueprint $table) {
            $table->string('id')->primary();
            $table->foreignId('user_id')->nullable()->index();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->longText('payload');
            $table->integer('last_activity')->index();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sessions');
        Schema::dropIfExists('password_reset_tokens');
        Schema::dropIfExists('users');
    }
};
