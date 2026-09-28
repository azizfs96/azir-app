<?php

namespace Database\Factories;

use App\Models\Staff;
use App\Models\Store;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Staff> */
class StaffFactory extends Factory
{
    public function definition(): array
    {
        return [
            'store_id' => Store::factory(),
            'name' => fake()->firstName('female'),
            'title_ar' => 'مصففة',
            'title_en' => 'Stylist',
            'is_active' => true,
            'is_bookable' => true,
        ];
    }

    public function forStore(Store $store): static
    {
        return $this->state(fn () => [
            'store_id' => $store->id,
            'merchant_id' => $store->merchant_id,
        ]);
    }
}
