<?php

namespace Tests\Feature;

use App\Engines\BusinessEngineRegistry;
use App\Engines\Restaurant\RestaurantEngine;
use App\Models\Branch;
use App\Models\Merchant;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Store;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ============================================================================
 * THE RESTAURANT ENGINE, PHASE R0 (spec §43/§44 — the second vertical)
 *
 * What these tests pin down:
 *   · the engine resolves from business_type with zero core changes
 *   · the merchant menu API is fully tenant-isolated, like every other CRUD
 *   · the option tree is validated as a BUSINESS structure (an unfulfillable
 *     group must be refused, not stored)
 *   · the public storefront serves the menu for restaurants and is
 *     byte-compatible for beauty stores — the verticals cannot bleed
 * ============================================================================
 */
class RestaurantMenuTest extends TestCase
{
    use RefreshDatabase;

    private Merchant $merchant;

    private Store $store;

    private User $owner;

    protected function setUp(): void
    {
        parent::setUp();

        $this->merchant = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($this->merchant);

        $this->store = Store::factory()->create([
            'merchant_id' => $this->merchant->id,
            'business_type' => 'restaurant',
            'name_ar' => 'برجر بلد',
            'name_en' => 'Balad Burger',
        ]);

        Branch::factory()->forStore($this->store)->create();

        $this->owner = User::factory()->create([
            'role' => 'merchant_owner',
            'merchant_id' => $this->merchant->id,
        ]);

        app(TenantContext::class)->setTenant(null);
    }

    private function asOwner(): static
    {
        $this->actingAs($this->owner);
        app(TenantContext::class)->setTenant($this->merchant);

        return $this;
    }

    // ---- the engine boundary ----------------------------------------------

    public function test_business_type_resolves_the_restaurant_engine(): void
    {
        $engine = app(BusinessEngineRegistry::class)->for($this->store);

        $this->assertInstanceOf(RestaurantEngine::class, $engine);
        $this->assertSame('restaurant', $engine->key());
    }

    public function test_the_restaurant_flow_is_menu_cart_confirm(): void
    {
        $steps = array_column(
            app(BusinessEngineRegistry::class)->for($this->store)->flow($this->store),
            'step',
        );

        $this->assertSame(['menu', 'cart', 'payment', 'confirm'], $steps);
    }

    public function test_onboarding_accepts_restaurant_as_a_business_type(): void
    {
        $response = $this->postJson('/api/v1/auth/merchant/register', [
            'business_name' => 'مطعم الاختبار',
            'business_type' => 'restaurant',
            'owner_name' => 'صاحب المطعم',
            'email' => 'resto@example.com',
            'phone' => '0555555555',
            'password' => 'password123',
        ]);

        $response->assertCreated();

        $this->assertSame(
            'restaurant',
            Store::withoutGlobalScopes()->latest('id')->value('business_type'),
        );
    }

    // ---- merchant menu CRUD ------------------------------------------------

    public function test_a_merchant_builds_a_menu(): void
    {
        $this->asOwner();

        $category = $this->postJson('/api/v1/merchant/menu/categories', [
            'name_ar' => 'البرجر',
            'name_en' => 'Burgers',
        ])->assertCreated()->json();

        $item = $this->postJson('/api/v1/merchant/menu/items', [
            'name_ar' => 'بيج تيستي',
            'name_en' => 'Big Tasty',
            'description_ar' => 'برجر لحم مع صوص خاص',
            'menu_category_id' => $category['id'],
            'price' => 32.00,
            'calories' => 850,
        ])->assertCreated()->json();

        $this->assertSame(32.0, (float) $item['price']);
        $this->assertSame($category['id'], $item['category_id']);

        // The Jahez two-group pattern: required size + optional extras.
        $updated = $this->putJson("/api/v1/merchant/menu/items/{$item['id']}/options", [
            'groups' => [
                [
                    'name_ar' => 'الحجم',
                    'min_select' => 1,
                    'max_select' => 1,
                    'options' => [
                        ['name_ar' => 'وسط', 'price_delta' => 0],
                        ['name_ar' => 'كبير', 'price_delta' => 5.00],
                    ],
                ],
                [
                    'name_ar' => 'الإضافات',
                    'min_select' => 0,
                    'max_select' => 3,
                    'options' => [
                        ['name_ar' => 'جبن إضافي', 'price_delta' => 3.00],
                        ['name_ar' => 'بدون بصل', 'price_delta' => 0],
                    ],
                ],
            ],
        ])->assertOk()->json();

        $this->assertCount(2, $updated['option_groups']);
        $this->assertTrue($updated['option_groups'][0]['required']);
        $this->assertFalse($updated['option_groups'][1]['required']);
        $this->assertSame(5.0, (float) $updated['option_groups'][0]['options'][1]['price_delta']);
    }

    public function test_replacing_the_option_tree_is_total_not_additive(): void
    {
        $this->asOwner();

        $item = $this->postJson('/api/v1/merchant/menu/items', [
            'name_ar' => 'شاورما', 'price' => 15,
        ])->assertCreated()->json();

        $sizeGroup = [
            'name_ar' => 'الحجم', 'min_select' => 1, 'max_select' => 1,
            'options' => [['name_ar' => 'وسط'], ['name_ar' => 'كبير']],
        ];

        $this->putJson("/api/v1/merchant/menu/items/{$item['id']}/options", [
            'groups' => [$sizeGroup],
        ])->assertOk();

        // Save again with a DIFFERENT single group — the old one must be gone.
        $result = $this->putJson("/api/v1/merchant/menu/items/{$item['id']}/options", [
            'groups' => [[
                'name_ar' => 'الخبز', 'min_select' => 1, 'max_select' => 1,
                'options' => [['name_ar' => 'صاج'], ['name_ar' => 'صمون']],
            ]],
        ])->assertOk()->json();

        $this->assertCount(1, $result['option_groups']);
        $this->assertSame('الخبز', $result['option_groups'][0]['name_ar']);

        // And an empty save clears everything.
        $cleared = $this->putJson("/api/v1/merchant/menu/items/{$item['id']}/options", [
            'groups' => [],
        ])->assertOk()->json();

        $this->assertCount(0, $cleared['option_groups']);
    }

    public function test_an_unfulfillable_option_group_is_refused(): void
    {
        $this->asOwner();

        $item = $this->postJson('/api/v1/merchant/menu/items', [
            'name_ar' => 'بيتزا', 'price' => 40,
        ])->assertCreated()->json();

        // min > max: no selection count can ever satisfy it.
        $this->putJson("/api/v1/merchant/menu/items/{$item['id']}/options", [
            'groups' => [[
                'name_ar' => 'الحجم', 'min_select' => 2, 'max_select' => 1,
                'options' => [['name_ar' => 'وسط'], ['name_ar' => 'كبير']],
            ]],
        ])->assertStatus(422)->assertJsonPath('error_code', 'OPTION_GROUP_INVALID');

        // min > number of options: equally impossible.
        $this->putJson("/api/v1/merchant/menu/items/{$item['id']}/options", [
            'groups' => [[
                'name_ar' => 'الصوصات', 'min_select' => 3, 'max_select' => 3,
                'options' => [['name_ar' => 'ثوم'], ['name_ar' => 'حار']],
            ]],
        ])->assertStatus(422)->assertJsonPath('error_code', 'OPTION_GROUP_INVALID');

        // Neither attempt may leave partial state behind.
        $this->assertSame(0, $item ? \App\Models\MenuOptionGroup::withoutGlobalScopes()->count() : -1);
    }

    public function test_a_category_from_another_merchant_cannot_be_referenced(): void
    {
        // Another merchant with their own category.
        $other = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($other);
        $otherStore = Store::factory()->create([
            'merchant_id' => $other->id, 'business_type' => 'restaurant',
        ]);
        $foreign = MenuCategory::create([
            'store_id' => $otherStore->id, 'name_ar' => 'مشروبات الغير',
        ]);
        app(TenantContext::class)->setTenant(null);

        $this->asOwner();

        $this->postJson('/api/v1/merchant/menu/items', [
            'name_ar' => 'دخيل', 'price' => 10, 'menu_category_id' => $foreign->id,
        ])->assertStatus(422);
    }

    public function test_menu_rows_are_tenant_isolated(): void
    {
        $this->asOwner();
        $item = $this->postJson('/api/v1/merchant/menu/items', [
            'name_ar' => 'برجر دجاج', 'price' => 22,
        ])->assertCreated()->json();

        // A different merchant's owner cannot see or touch it.
        $other = Merchant::factory()->create(['status' => 'approved']);
        $otherOwner = User::factory()->create([
            'role' => 'merchant_owner', 'merchant_id' => $other->id,
        ]);
        app(TenantContext::class)->setTenant($other);
        Store::factory()->create(['merchant_id' => $other->id, 'business_type' => 'restaurant']);

        $this->actingAs($otherOwner);
        app(TenantContext::class)->setTenant($other);

        $this->getJson('/api/v1/merchant/menu/items')
            ->assertOk()
            ->assertJsonCount(0, 'data');

        // Cross-tenant reads are 404, never 403 (§4: do not confirm existence).
        $this->putJson("/api/v1/merchant/menu/items/{$item['id']}", ['price' => 1])
            ->assertNotFound();
    }

    // ---- the public storefront --------------------------------------------

    public function test_the_storefront_serves_the_menu_tree(): void
    {
        $this->asOwner();

        $category = $this->postJson('/api/v1/merchant/menu/categories', [
            'name_ar' => 'البرجر', 'name_en' => 'Burgers',
        ])->json();

        $item = $this->postJson('/api/v1/merchant/menu/items', [
            'name_ar' => 'بيج تيستي', 'menu_category_id' => $category['id'], 'price' => 32,
        ])->json();

        $this->putJson("/api/v1/merchant/menu/items/{$item['id']}/options", [
            'groups' => [[
                'name_ar' => 'الحجم', 'min_select' => 1, 'max_select' => 1,
                'options' => [['name_ar' => 'وسط'], ['name_ar' => 'كبير', 'price_delta' => 5]],
            ]],
        ])->assertOk();

        // Sold-out and inactive dishes exist for the merchant but must not
        // reach customers.
        $this->postJson('/api/v1/merchant/menu/items', [
            'name_ar' => 'مخفي', 'menu_category_id' => $category['id'],
            'price' => 9, 'is_active' => false,
        ])->assertCreated();

        app(TenantContext::class)->setTenant(null);
        $this->app->forgetInstance(TenantContext::class);

        $json = $this->getJson("/api/v1/stores/{$this->store->public_token}")
            ->assertOk()
            ->json();

        $this->assertSame('restaurant', $json['store']['type']);
        $this->assertSame(['menu', 'cart', 'payment', 'confirm'], array_column($json['flow'], 'step'));

        $menu = $json['menu'];
        $this->assertCount(1, $menu['categories']);
        $this->assertSame('البرجر', $menu['categories'][0]['name_ar']);

        $dishes = $menu['categories'][0]['items'];
        $this->assertCount(1, $dishes, 'An inactive dish leaked to the storefront.');
        $this->assertSame('بيج تيستي', $dishes[0]['name_ar']);
        $this->assertSame(5.0, (float) $dishes[0]['option_groups'][0]['options'][1]['price_delta']);

        // Restaurant configuration falls back to the engine's defaults.
        $this->assertTrue($json['configuration']['order_pickup']);
        $this->assertFalse($json['configuration']['auto_accept_orders']);
    }

    public function test_a_dish_can_be_marked_featured_and_it_reaches_the_storefront(): void
    {
        $this->asOwner();

        $item = $this->postJson('/api/v1/merchant/menu/items', [
            'name_ar' => 'بيج تيستي', 'price' => 32, 'is_featured' => true,
        ])->assertCreated()->json();

        $this->assertTrue($item['is_featured']);

        // Toggling it off round-trips too.
        $off = $this->putJson("/api/v1/merchant/menu/items/{$item['id']}", [
            'is_featured' => false,
        ])->assertOk()->json();
        $this->assertFalse($off['is_featured']);

        // ...and the flag survives to the public storefront.
        $this->putJson("/api/v1/merchant/menu/items/{$item['id']}", ['is_featured' => true])->assertOk();

        app(TenantContext::class)->setTenant(null);
        $this->app->forgetInstance(TenantContext::class);

        $json = $this->getJson("/api/v1/stores/{$this->store->public_token}")->assertOk()->json();

        $this->assertTrue($json['menu']['uncategorised'][0]['is_featured']);
    }

    public function test_a_category_carries_an_image_field(): void
    {
        $this->asOwner();

        $category = $this->postJson('/api/v1/merchant/menu/categories', [
            'name_ar' => 'البرجر',
        ])->assertCreated()->json();

        // The key is present (null until an image is uploaded), so the
        // dashboard and app can rely on its shape.
        $this->assertArrayHasKey('image', $category);
        $this->assertNull($category['image']);
    }

    public function test_beauty_storefronts_are_untouched_by_the_new_vertical(): void
    {
        // The existing seeded beauty store from other suites is not available
        // here; build a minimal one.
        $beautyMerchant = Merchant::factory()->create(['status' => 'approved']);
        app(TenantContext::class)->setTenant($beautyMerchant);
        $beauty = Store::factory()->create([
            'merchant_id' => $beautyMerchant->id,
            'business_type' => 'beauty_wellness',
        ]);
        Branch::factory()->forStore($beauty)->create();
        app(TenantContext::class)->setTenant(null);

        $json = $this->getJson("/api/v1/stores/{$beauty->public_token}")
            ->assertOk()
            ->json();

        $this->assertSame('beauty_wellness', $json['store']['type']);
        $this->assertArrayNotHasKey('menu', $json, 'Beauty payloads must not grow a menu key.');
        $this->assertContains('service', array_column($json['flow'], 'step'));
    }
}
