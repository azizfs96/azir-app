<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Links merchant_owner / merchant_staff users to their tenant.
 *
 * This is THE source of truth for tenancy: TenantContext reads merchant_id from
 * the authenticated user and never from the request (ARCHITECTURE.md §4).
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->foreignId('merchant_id')
                ->nullable()
                ->after('role')
                ->constrained('merchants')
                ->cascadeOnDelete();

            $table->index(['merchant_id', 'role']);
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropForeign(['merchant_id']);
            $table->dropIndex(['merchant_id', 'role']);
            $table->dropColumn('merchant_id');
        });
    }
};
