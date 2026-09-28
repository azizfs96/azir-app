<?php

namespace Database\Factories;

use App\Models\Merchant;
use App\Models\Store;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Store> */
class StoreFactory extends Factory
{
    public function definition(): array
    {
        return [
            'merchant_id' => Merchant::factory(),
            'business_type' => 'beauty_wellness',
            'name_ar' => 'صالون '.fake()->firstName(),
            'name_en' => fake()->company().' Beauty',
            'timezone' => 'Asia/Riyadh',
            'currency' => 'SAR',
            'gender_policy' => 'all',
            'is_published' => true,
            'published_at' => now(),
        ];
    }

    public function unpublished(): static
    {
        return $this->state(fn () => ['is_published' => false, 'published_at' => null]);
    }
}
