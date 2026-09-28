<?php

namespace Database\Factories;

use App\Models\Service;
use App\Models\Store;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Service> */
class ServiceFactory extends Factory
{
    public function definition(): array
    {
        $catalog = [
            ['قص شعر', 'Hair Cut', 100, 30],
            ['صبغة شعر', 'Hair Color', 250, 120],
            ['تنظيف بشرة', 'Facial', 180, 60],
            ['مساج', 'Massage', 200, 60],
        ];

        [$ar, $en, $price, $duration] = fake()->randomElement($catalog);

        return [
            'store_id' => Store::factory(),
            'name_ar' => $ar,
            'name_en' => $en,
            'price' => $price,
            'currency' => 'SAR',
            'duration_minutes' => $duration,
            'is_active' => true,
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
