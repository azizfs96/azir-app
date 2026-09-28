<?php

namespace Database\Factories;

use App\Models\Merchant;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Facades\Hash;

/**
 * @extends Factory<User>
 */
class UserFactory extends Factory
{
    protected static ?string $password;

    public function definition(): array
    {
        return [
            'name' => fake()->name(),
            'email' => fake()->unique()->safeEmail(),
            'email_verified_at' => now(),
            'phone' => '+9665'.fake()->unique()->numerify('########'),
            'phone_verified_at' => now(),
            'password' => static::$password ??= Hash::make('password'),
            'role' => User::ROLE_CUSTOMER,
            'locale' => 'ar',
            'is_active' => true,
        ];
    }

    /** A phone-and-OTP customer: no email, no password (spec §34). */
    public function customer(): static
    {
        return $this->state(fn () => [
            'role' => User::ROLE_CUSTOMER,
            'email' => null,
            'password' => null,
        ]);
    }

    public function merchantOwner(?Merchant $merchant = null): static
    {
        return $this->state(fn () => [
            'role' => User::ROLE_MERCHANT_OWNER,
            'merchant_id' => $merchant?->id,
        ]);
    }

    public function merchantStaff(?Merchant $merchant = null): static
    {
        return $this->state(fn () => [
            'role' => User::ROLE_MERCHANT_STAFF,
            'merchant_id' => $merchant?->id,
        ]);
    }

    public function admin(): static
    {
        return $this->state(fn () => ['role' => User::ROLE_ADMIN, 'merchant_id' => null]);
    }

    public function unverified(): static
    {
        return $this->state(fn () => ['email_verified_at' => null, 'phone_verified_at' => null]);
    }
}
