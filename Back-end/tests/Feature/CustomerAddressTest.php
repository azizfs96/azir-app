<?php

namespace Tests\Feature;

use App\Models\Customer;
use App\Models\CustomerAddress;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * CENTRAL DELIVERY ADDRESSES (feature expansion)
 *
 * Addresses belong to the platform customer, not a store. These tests prove the
 * CRUD, the "exactly one default" invariant, and — most important — that a
 * customer only ever sees and touches their own addresses.
 * ============================================================================
 */
class CustomerAddressTest extends TestCase
{
    use RefreshDatabase;

    private function customer(): User
    {
        $user = User::factory()->create(['role' => 'customer']);
        Customer::factory()->create(['user_id' => $user->id]);

        return $user->fresh();
    }

    public function test_the_first_saved_address_becomes_the_default(): void
    {
        $user = $this->customer();

        $this->actingAs($user)->postJson('/api/v1/me/addresses', [
            'label' => 'home',
            'address_text' => 'حي الورود',
        ])->assertCreated()->assertJsonPath('is_default', true);
    }

    public function test_marking_a_new_default_demotes_the_previous_one(): void
    {
        $user = $this->customer();

        $first = $this->actingAs($user)->postJson('/api/v1/me/addresses', [
            'address_text' => 'الأول',
        ])->json('id');

        $second = $this->actingAs($user)->postJson('/api/v1/me/addresses', [
            'address_text' => 'الثاني', 'is_default' => true,
        ])->json('id');

        $this->assertFalse(CustomerAddress::find($first)->is_default);
        $this->assertTrue(CustomerAddress::find($second)->is_default);
    }

    public function test_a_customer_lists_only_their_own_addresses(): void
    {
        $mine = $this->customer();
        $other = $this->customer();

        $this->actingAs($mine)->postJson('/api/v1/me/addresses', ['address_text' => 'لي'])->assertCreated();
        $this->actingAs($other)->postJson('/api/v1/me/addresses', ['address_text' => 'له'])->assertCreated();

        $this->actingAs($mine)->getJson('/api/v1/me/addresses')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.address_text', 'لي');
    }

    public function test_a_customer_cannot_edit_someone_elses_address(): void
    {
        $mine = $this->customer();
        $other = $this->customer();

        $strangerId = $this->actingAs($other)
            ->postJson('/api/v1/me/addresses', ['address_text' => 'له'])->json('id');

        $this->actingAs($mine)->putJson("/api/v1/me/addresses/{$strangerId}", [
            'address_text' => 'اختراق',
        ])->assertNotFound();

        $this->assertSame('له', CustomerAddress::find($strangerId)->address_text);
    }

    public function test_deleting_the_default_promotes_another(): void
    {
        $user = $this->customer();

        $first = $this->actingAs($user)->postJson('/api/v1/me/addresses', ['address_text' => 'الأول'])->json('id');
        $second = $this->actingAs($user)->postJson('/api/v1/me/addresses', ['address_text' => 'الثاني'])->json('id');

        // 'first' is the default (first saved); delete it.
        $this->actingAs($user)->deleteJson("/api/v1/me/addresses/{$first}")->assertNoContent();

        $this->assertNull(CustomerAddress::find($first));
        $this->assertTrue(CustomerAddress::find($second)->is_default);
    }
}
