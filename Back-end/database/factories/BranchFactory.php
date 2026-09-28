<?php

namespace Database\Factories;

use App\Models\Branch;
use App\Models\Store;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Branch> */
class BranchFactory extends Factory
{
    public function definition(): array
    {
        return [
            'store_id' => Store::factory(),
            'name_ar' => 'فرع '.fake()->randomElement(['العليا', 'الملقا', 'النخيل']),
            'name_en' => fake()->randomElement(['Olaya', 'Al Malqa', 'Al Nakheel']),
            'city' => 'Riyadh',
            'slot_interval_minutes' => 15,
            'is_active' => true,
        ];
    }

    /** merchant_id is inherited from the store when created via a store. */
    public function forStore(Store $store): static
    {
        return $this->state(fn () => [
            'store_id' => $store->id,
            'merchant_id' => $store->merchant_id,
        ]);
    }
}
