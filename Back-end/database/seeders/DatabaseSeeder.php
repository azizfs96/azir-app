<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    /**
     * Seed the application's database.
     *
     * Production seed: the Azir restaurant store, complete with its menu,
     * images, VAT/invoicing settings and fulfilment config — so a fresh
     * deployment is ready without any manual data entry.
     */
    public function run(): void
    {
        $this->call(AzirRestaurantSeeder::class);
    }
}
