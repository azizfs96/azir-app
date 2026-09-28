<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Merchant;
use App\Models\Store;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * ADMIN MERCHANT APPROVAL (spec §39)
 *
 * The gap this closes: a merchant registers as `pending`, and a pending
 * merchant's store is unreachable — every printed QR returns 404. Without an
 * approval path, nobody could ever go live except by editing the database.
 * ============================================================================
 */
class AdminMerchantApprovalTest extends TestCase
{
    use RefreshDatabase;

    private string $adminToken;

    protected function setUp(): void
    {
        parent::setUp();

        $admin = User::factory()->admin()->create([
            'email' => 'admin@wasla.sa',
            'password' => 'secret-password',
        ]);

        $this->adminToken = $admin->createToken('admin')->plainTextToken;
    }

    /** A pending merchant with an otherwise complete, published store. */
    private function pendingMerchant(string $name = 'Glow Beauty'): Merchant
    {
        $merchant = Merchant::factory()->pending()->create(['display_name' => $name]);

        app(TenantContext::class)->setTenant($merchant);
        $store = Store::factory()->create(['merchant_id' => $merchant->id]);
        $store->forceFill(['is_published' => true])->save();
        app(TenantContext::class)->setTenant(null);

        return $merchant->fresh();
    }

    private function admin(): self
    {
        $this->app['auth']->forgetGuards();

        return $this->withToken($this->adminToken);
    }

    // =====================================================================
    // The approval queue
    // =====================================================================

    public function test_the_queue_lists_pending_merchants_first(): void
    {
        Merchant::factory()->create(['display_name' => 'Already Approved']);
        $this->pendingMerchant('Waiting For Review');

        $response = $this->admin()->getJson('/api/v1/admin/merchants')->assertOk();

        // The admin's job is the queue, so it should not need a filter to find
        // its own work.
        $this->assertSame('Waiting For Review', $response->json('data.data.0.display_name'));
    }

    public function test_the_queue_can_be_filtered_by_status(): void
    {
        Merchant::factory()->create(['display_name' => 'Approved One']);
        $this->pendingMerchant('Pending One');

        $response = $this->admin()
            ->getJson('/api/v1/admin/merchants?status=pending')
            ->assertOk();

        $this->assertCount(1, $response->json('data.data'));
        $this->assertSame('Pending One', $response->json('data.data.0.display_name'));
    }

    // =====================================================================
    // Approval — the thing that actually makes a store reachable
    // =====================================================================

    public function test_a_pending_merchants_qr_does_not_resolve(): void
    {
        $merchant = $this->pendingMerchant();
        $token = $merchant->store->public_token;

        // Published, but the merchant is not approved — so nobody can reach it.
        $this->getJson("/api/v1/stores/{$token}")->assertStatus(404);
    }

    public function test_approving_makes_the_qr_resolve(): void
    {
        $merchant = $this->pendingMerchant();
        $token = $merchant->store->public_token;

        $this->admin()
            ->postJson("/api/v1/admin/merchants/{$merchant->id}/approve")
            ->assertOk()
            ->assertJsonPath('merchant.status', 'approved');

        // THE PAYOFF: the same printed QR now opens the store.
        $this->app['auth']->forgetGuards();
        $this->getJson("/api/v1/stores/{$token}")
            ->assertOk()
            ->assertJsonPath('store.token', $token);
    }

    public function test_approving_twice_is_refused(): void
    {
        $merchant = Merchant::factory()->create();

        $this->admin()
            ->postJson("/api/v1/admin/merchants/{$merchant->id}/approve")
            ->assertStatus(422)
            ->assertJsonPath('error_code', 'ALREADY_APPROVED');
    }

    // =====================================================================
    // Suspension — must take effect immediately
    // =====================================================================

    public function test_suspending_stops_the_qr_from_resolving(): void
    {
        $merchant = $this->pendingMerchant();
        $token = $merchant->store->public_token;

        $this->admin()->postJson("/api/v1/admin/merchants/{$merchant->id}/approve");

        $this->app['auth']->forgetGuards();
        $this->getJson("/api/v1/stores/{$token}")->assertOk();

        $this->admin()->postJson("/api/v1/admin/merchants/{$merchant->id}/suspend", [
            'reason' => 'Complaints about no-shows',
        ])->assertOk()->assertJsonPath('merchant.status', 'suspended');

        // Every printed code stops working the moment suspension lands.
        $this->app['auth']->forgetGuards();
        $this->getJson("/api/v1/stores/{$token}")->assertStatus(404);
    }

    public function test_suspension_requires_a_reason(): void
    {
        $merchant = Merchant::factory()->create();

        $this->admin()
            ->postJson("/api/v1/admin/merchants/{$merchant->id}/suspend")
            ->assertStatus(422);
    }

    public function test_a_suspended_merchant_can_be_reinstated(): void
    {
        $merchant = Merchant::factory()->suspended()->create();

        $this->admin()
            ->postJson("/api/v1/admin/merchants/{$merchant->id}/reinstate")
            ->assertOk()
            ->assertJsonPath('merchant.status', 'approved');

        $this->assertNull($merchant->fresh()->suspended_at);
    }

    public function test_rejecting_unpublishes_the_store(): void
    {
        $merchant = $this->pendingMerchant();

        $this->admin()->postJson("/api/v1/admin/merchants/{$merchant->id}/reject", [
            'reason' => 'Could not verify the business',
        ])->assertOk()->assertJsonPath('merchant.status', 'rejected');

        // A rejected merchant must not remain reachable by a printed QR.
        $this->assertFalse((bool) $merchant->store->fresh()->is_published);
    }

    // =====================================================================
    // Audit trail (spec §35)
    // =====================================================================

    public function test_every_decision_is_audited(): void
    {
        $merchant = $this->pendingMerchant();

        $this->admin()->postJson("/api/v1/admin/merchants/{$merchant->id}/approve");
        $this->admin()->postJson("/api/v1/admin/merchants/{$merchant->id}/suspend", [
            'reason' => 'Test suspension',
        ]);

        $logs = AuditLog::orderBy('id')->get();

        $this->assertSame(
            ['merchant.approved', 'merchant.suspended'],
            $logs->pluck('action')->all(),
        );

        $suspension = $logs->last();
        $this->assertSame('Test suspension', $suspension->new_values['reason']);
        $this->assertSame($merchant->id, $suspension->merchant_id);
        $this->assertNotNull($suspension->user_id, 'The acting admin must be recorded');

        // Privacy: the trail records who and what, never a raw IP.
        $this->assertNotSame('127.0.0.1', $suspension->ip_hash);
    }

    // =====================================================================
    // Access control
    // =====================================================================

    public function test_a_merchant_cannot_reach_the_admin_api(): void
    {
        $merchant = Merchant::factory()->create();
        $owner = User::factory()->merchantOwner($merchant)->create();
        $token = $owner->createToken('dashboard')->plainTextToken;

        $this->app['auth']->forgetGuards();

        // A merchant approving themselves would defeat the entire point.
        $this->withToken($token)
            ->postJson("/api/v1/admin/merchants/{$merchant->id}/approve")
            ->assertStatus(403);

        $this->assertSame(Merchant::STATUS_APPROVED, $merchant->fresh()->status);
    }

    public function test_a_customer_cannot_reach_the_admin_api(): void
    {
        $user = User::factory()->customer()->create();
        $token = $user->createToken('app')->plainTextToken;

        $this->app['auth']->forgetGuards();

        $this->withToken($token)->getJson('/api/v1/admin/merchants')->assertStatus(403);
    }

    public function test_metrics_report_the_platform(): void
    {
        $this->pendingMerchant();
        Merchant::factory()->create();

        $this->admin()->getJson('/api/v1/admin/metrics')
            ->assertOk()
            ->assertJsonPath('merchants.pending', 1)
            ->assertJsonStructure([
                'merchants' => ['total', 'pending', 'approved', 'suspended'],
                'stores' => ['total', 'published'],
                'customers' => ['total'],
                'bookings' => ['total', 'completed'],
                'qr' => ['total_scans'],
            ]);
    }
}
