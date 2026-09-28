<?php

namespace Database\Factories;

use App\Models\Customer;
use App\Models\CustomerCar;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<CustomerCar> */
class CustomerCarFactory extends Factory
{
    public function definition(): array
    {
        return [
            'customer_id' => Customer::factory(),
            'brand' => 'تويوتا',
            'color' => 'أبيض',
            'plate_letters' => 'أ ب ج',
            'plate_numbers' => (string) fake()->numberBetween(1000, 9999),
            'is_default' => false,
        ];
    }

    public function default(): static
    {
        return $this->state(fn () => ['is_default' => true]);
    }
}
