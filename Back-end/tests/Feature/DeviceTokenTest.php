<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\DeviceToken;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Registering a device for push (spec §23): idempotent per (user, token), and a
 * token that moves to another account is reassigned, not duplicated.
 */
class DeviceTokenTest extends TestCase
{
    use RefreshDatabase;

    private function customer(): User
    {
        $user = User::factory()->create(['role' => 'customer']);
        Customer::factory()->create(['user_id' => $user->id]);

        return $user->fresh();
    }

    public function test_a_customer_registers_a_device_token(): void
    {
        $user = $this->customer();

        $this->actingAs($user)->postJson('/api/v1/me/device-tokens', [
            'token' => 'fcm-token-1',
            'platform' => 'ios',
            'app_version' => '1.0.0',
        ])->assertNoContent();

        $this->assertDatabaseHas('device_tokens', [
            'user_id' => $user->id,
            'token' => 'fcm-token-1',
            'platform' => 'ios',
        ]);
    }

    public function test_registering_the_same_token_twice_updates_in_place(): void
    {
        $user = $this->customer();

        $this->actingAs($user)->postJson('/api/v1/me/device-tokens', [
            'token' => 'fcm-token-1', 'platform' => 'ios', 'app_version' => '1.0.0',
        ])->assertNoContent();

        $this->actingAs($user)->postJson('/api/v1/me/device-tokens', [
            'token' => 'fcm-token-1', 'platform' => 'ios', 'app_version' => '1.1.0',
        ])->assertNoContent();

        $this->assertSame(1, DeviceToken::where('token', 'fcm-token-1')->count());
        $this->assertDatabaseHas('device_tokens', ['token' => 'fcm-token-1', 'app_version' => '1.1.0']);
    }

    public function test_a_token_that_moves_to_another_account_is_reassigned(): void
    {
        $first = $this->customer();
        $second = $this->customer();

        $this->actingAs($first)->postJson('/api/v1/me/device-tokens', [
            'token' => 'shared-device', 'platform' => 'ios',
        ])->assertNoContent();

        $this->actingAs($second)->postJson('/api/v1/me/device-tokens', [
            'token' => 'shared-device', 'platform' => 'ios',
        ])->assertNoContent();

        $this->assertSame(1, DeviceToken::where('token', 'shared-device')->count());
        $this->assertDatabaseHas('device_tokens', [
            'token' => 'shared-device', 'user_id' => $second->id,
        ]);
    }

    public function test_a_customer_removes_their_device_token(): void
    {
        $user = $this->customer();
        $user->deviceTokens()->create(['token' => 'gone', 'platform' => 'ios']);

        $this->actingAs($user)->deleteJson('/api/v1/me/device-tokens', ['token' => 'gone'])
            ->assertNoContent();

        $this->assertDatabaseMissing('device_tokens', ['token' => 'gone']);
    }

    public function test_registration_requires_auth(): void
    {
        $this->postJson('/api/v1/me/device-tokens', ['token' => 'x', 'platform' => 'ios'])
            ->assertUnauthorized();
    }
}
