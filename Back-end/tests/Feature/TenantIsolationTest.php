<?php

namespace Tests\Feature;

use App\Models\Branch;
use App\Models\Merchant;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use App\Models\User;
use App\Policies\ServicePolicy;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * THE TENANT ISOLATION GATE (spec §26, §35 / ARCHITECTURE.md §4, §12 risk 7).
 *
 *   "Each merchant must only access their own [data]. Never rely only on
 *    frontend restrictions."
 *
 * These tests assert that merchant A cannot see or touch merchant B's rows
 * through any of the three defence layers:
 *
 *   Layer 1  TenantContext derives the tenant from the USER only
 *   Layer 2  BelongsToTenant global scope filters every query
 *   Layer 3  Policies reject cross-tenant records
 *
 * If any test here fails, the platform is not safe to run. This is a release
 * gate, not a nice-to-have.
 * ============================================================================
 */
class TenantIsolationTest extends TestCase
{
    use RefreshDatabase;

    private Merchant $merchantA;

    private Merchant $merchantB;

    private User $ownerA;

    private User $ownerB;

    private Store $storeA;

    private Store $storeB;

    protected function setUp(): void
    {
        parent::setUp();

        // Two entirely unrelated businesses on the same platform.
        $this->merchantA = Merchant::factory()->create(['display_name' => 'Glow Beauty']);
        $this->merchantB = Merchant::factory()->create(['display_name' => 'ABC Spa']);

        $this->ownerA = User::factory()->merchantOwner($this->merchantA)->create();
        $this->ownerB = User::factory()->merchantOwner($this->merchantB)->create();

        $this->storeA = Store::factory()->create(['merchant_id' => $this->merchantA->id]);
        $this->storeB = Store::factory()->create(['merchant_id' => $this->merchantB->id]);
    }

    /**
     * Put the app into "acting as this merchant" state, exactly as the
     * ResolveTenant middleware would.
     */
    private function actAsTenant(Merchant $merchant): void
    {
        app(TenantContext::class)->setTenant($merchant);
    }

    // ---------------------------------------------------------------------
    // Layer 2 — the global scope
    // ---------------------------------------------------------------------

    public function test_store_queries_only_return_the_active_tenants_rows(): void
    {
        $this->actAsTenant($this->merchantA);

        $stores = Store::all();

        $this->assertCount(1, $stores);
        $this->assertTrue($stores->first()->is($this->storeA));
    }

    public function test_a_query_for_another_tenants_record_by_id_finds_nothing(): void
    {
        $this->actAsTenant($this->merchantA);

        // Merchant A knows B's primary key and asks for it directly.
        // The global scope must make it simply not exist.
        $this->assertNull(Store::find($this->storeB->id));
    }

    public function test_services_branches_and_staff_are_all_scoped(): void
    {
        Service::factory()->forStore($this->storeA)->create();
        Service::factory()->forStore($this->storeB)->create();
        Branch::factory()->forStore($this->storeA)->create();
        Branch::factory()->forStore($this->storeB)->create();
        Staff::factory()->forStore($this->storeA)->create();
        Staff::factory()->forStore($this->storeB)->create();

        $this->actAsTenant($this->merchantA);

        $this->assertCount(1, Service::all(), 'Services leaked across tenants');
        $this->assertCount(1, Branch::all(), 'Branches leaked across tenants');
        $this->assertCount(1, Staff::all(), 'Staff leaked across tenants');

        $this->assertSame($this->merchantA->id, Service::first()->merchant_id);
        $this->assertSame($this->merchantA->id, Branch::first()->merchant_id);
        $this->assertSame($this->merchantA->id, Staff::first()->merchant_id);
    }

    public function test_aggregate_queries_cannot_count_another_tenants_rows(): void
    {
        Service::factory()->forStore($this->storeA)->count(2)->create();
        Service::factory()->forStore($this->storeB)->count(7)->create();

        $this->actAsTenant($this->merchantA);

        // A count() bypasses model hydration — the scope must still apply.
        $this->assertSame(2, Service::count());
    }

    // ---------------------------------------------------------------------
    // Auto-fill: application code never passes merchant_id, so it can never
    // pass the wrong one.
    // ---------------------------------------------------------------------

    public function test_new_records_are_stamped_with_the_active_tenant(): void
    {
        $this->actAsTenant($this->merchantA);

        $service = Service::create([
            'store_id' => $this->storeA->id,
            'name_ar' => 'قص شعر',
            'price' => 100,
            'duration_minutes' => 30,
        ]);

        $this->assertSame($this->merchantA->id, $service->merchant_id);
    }

    /**
     * A forged merchant_id must never be persisted.
     *
     * merchant_id is absent from every model's fillable list, so mass assigning
     * it is rejected outright. In local/CI, preventSilentlyDiscardingAttributes
     * turns that into a loud exception; in production the attribute is silently
     * dropped. Both outcomes are safe — this asserts the loud one, and the test
     * below asserts the silent one.
     */
    public function test_a_forged_merchant_id_is_rejected_loudly_in_development(): void
    {
        $this->actAsTenant($this->merchantA);

        $this->expectException(\Illuminate\Database\Eloquent\MassAssignmentException::class);

        Service::create([
            'store_id' => $this->storeA->id,
            'name_ar' => 'قص شعر',
            'price' => 100,
            'duration_minutes' => 30,
            'merchant_id' => $this->merchantB->id,
        ]);
    }

    public function test_a_forged_merchant_id_is_dropped_in_production(): void
    {
        // Production does not throw — it discards the non-fillable attribute.
        // The tenant stamp must still win.
        \Illuminate\Database\Eloquent\Model::preventSilentlyDiscardingAttributes(false);

        $this->actAsTenant($this->merchantA);

        $service = Service::create([
            'store_id' => $this->storeA->id,
            'name_ar' => 'قص شعر',
            'price' => 100,
            'duration_minutes' => 30,
            'merchant_id' => $this->merchantB->id,
        ]);

        $this->assertSame(
            $this->merchantA->id,
            $service->fresh()->merchant_id,
            'A merchant_id supplied by the client was trusted — tenant isolation is broken.'
        );

        \Illuminate\Database\Eloquent\Model::preventSilentlyDiscardingAttributes(true);
    }

    // ---------------------------------------------------------------------
    // Layer 3 — policies
    // ---------------------------------------------------------------------

    public function test_policy_refuses_a_cross_tenant_record(): void
    {
        $serviceB = Service::factory()->forStore($this->storeB)->create();
        $policy = new ServicePolicy;

        $this->assertFalse($policy->view($this->ownerA, $serviceB));
        $this->assertFalse($policy->update($this->ownerA, $serviceB));
        $this->assertFalse($policy->delete($this->ownerA, $serviceB));
    }

    public function test_policy_allows_a_merchants_own_record(): void
    {
        $serviceA = Service::factory()->forStore($this->storeA)->create();
        $policy = new ServicePolicy;

        $this->assertTrue($policy->view($this->ownerA, $serviceA));
        $this->assertTrue($policy->update($this->ownerA, $serviceA));
    }

    public function test_policy_refuses_a_customer_entirely(): void
    {
        $customer = User::factory()->customer()->create();
        $serviceA = Service::factory()->forStore($this->storeA)->create();

        $this->assertFalse((new ServicePolicy)->view($customer, $serviceA));
    }

    public function test_policy_refuses_a_deactivated_merchant_user(): void
    {
        $this->ownerA->update(['is_active' => false]);
        $serviceA = Service::factory()->forStore($this->storeA)->create();

        $this->assertFalse((new ServicePolicy)->view($this->ownerA->fresh(), $serviceA));
    }

    // ---------------------------------------------------------------------
    // The escape hatch, and its limits
    // ---------------------------------------------------------------------

    public function test_admin_escape_hatch_sees_everything_but_only_inside_the_callback(): void
    {
        Service::factory()->forStore($this->storeA)->create();
        Service::factory()->forStore($this->storeB)->create();

        $this->actAsTenant($this->merchantA);
        $tenant = app(TenantContext::class);

        $all = $tenant->withoutTenancy(fn () => Service::count());
        $this->assertSame(2, $all, 'withoutTenancy should see every tenant');

        // Crucially: scoping is restored afterwards.
        $this->assertSame(1, Service::count(), 'Tenant scoping was not restored');
    }

    public function test_scoping_is_restored_even_when_the_callback_throws(): void
    {
        $this->actAsTenant($this->merchantA);
        $tenant = app(TenantContext::class);

        try {
            $tenant->withoutTenancy(function (): void {
                throw new \RuntimeException('boom');
            });
        } catch (\RuntimeException) {
            // expected
        }

        Service::factory()->forStore($this->storeB)->create();

        $this->assertSame(0, Service::count(), 'A thrown exception left tenancy suspended');
    }

    public function test_no_tenant_context_means_no_scoping_for_public_lookups(): void
    {
        // Public store resolution by public_token runs unauthenticated, with no
        // tenant, and must still be able to find any published store (§7.1).
        $found = Store::where('public_token', $this->storeB->public_token)->first();

        $this->assertNotNull($found);
        $this->assertTrue($found->is($this->storeB));
    }
}
