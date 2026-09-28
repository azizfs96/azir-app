<?php

namespace Database\Factories;

use App\Models\Merchant;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Merchant> */
class MerchantFactory extends Factory
{
    public function definition(): array
    {
        $name = fake()->company();

        return [
            'owner_user_id' => User::factory(),
            'legal_name' => $name.' LLC',
            'display_name' => $name,
            'contact_phone' => '+9665'.fake()->numerify('########'),
            'contact_email' => fake()->unique()->companyEmail(),
            'status' => Merchant::STATUS_APPROVED,
            'onboarding_step' => Merchant::FINAL_ONBOARDING_STEP,
            'onboarded_at' => now(),
            'approved_at' => now(),
        ];
    }

    public function pending(): static
    {
        return $this->state(fn () => [
            'status' => Merchant::STATUS_PENDING,
            'approved_at' => null,
            'onboarded_at' => null,
            'onboarding_step' => 1,
        ]);
    }

    public function suspended(): static
    {
        return $this->state(fn () => [
            'status' => Merchant::STATUS_SUSPENDED,
            'suspended_at' => now(),
            'suspension_reason' => 'Testing',
        ]);
    }
}
