<?php

namespace Database\Seeders;

use App\Domain\Discovery\QrCodeService;
use App\Models\BookingSettings;
use App\Models\Branch;
use App\Models\MenuCategory;
use App\Models\MenuItem;
use App\Models\Merchant;
use App\Models\Store;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Database\Seeder;

/**
 * "سوق البركة" — a demo supermarket: delivery-only, paid on delivery, a
 * grocery catalogue with units, discounts and tracked stock.
 *
 * Owner login: owner@market.sa / SEED_OWNER_PASSWORD (default "password").
 * Product photos are not seeded (the merchant uploads them from the
 * dashboard); the storefront shows a category-tinted placeholder meanwhile.
 */
class SupermarketSeeder extends Seeder
{
    public function run(): void
    {
        if (Store::withoutGlobalScopes()->where('public_token', env('MARKET_STORE_TOKEN', 'AZRMRKT7'))->exists()) {
            return;
        }

        $password = env('SEED_OWNER_PASSWORD', 'password');

        $owner = new User;
        $owner->forceFill([
            'name' => 'Market Owner',
            'email' => 'owner@market.sa',
            'password' => $password,
            'role' => User::ROLE_MERCHANT_OWNER,
            'phone' => '+966555000333',
            'locale' => 'ar',
            'is_active' => true,
            'email_verified_at' => now(),
            'phone_verified_at' => now(),
        ])->save();

        $merchant = Merchant::create([
            'owner_user_id' => $owner->id,
            'legal_name' => 'مؤسسة سوق البركة التجارية',
            'display_name' => 'سوق البركة',
            'contact_phone' => '+966555000333',
            'contact_email' => 'owner@market.sa',
            'status' => Merchant::STATUS_APPROVED,
            'onboarding_step' => Merchant::FINAL_ONBOARDING_STEP,
        ]);
        $merchant->forceFill(['onboarded_at' => now(), 'approved_at' => now()])->save();
        $owner->forceFill(['merchant_id' => $merchant->id])->save();

        app(TenantContext::class)->setTenant($merchant);

        $store = Store::create([
            'merchant_id' => $merchant->id,
            // FIXED token (QR is printed): only store-alphabet chars (no 0 1 I L O U).
            'public_token' => env('MARKET_STORE_TOKEN', 'AZRMRKT7'),
            'name_ar' => 'سوق البركة',
            'name_en' => 'Baraka Market',
            'description_ar' => 'احتياجاتك اليومية تصلك إلى بابك',
            'description_en' => 'Your everyday essentials, delivered',
            'business_type' => 'supermarket',
            'gender_policy' => 'all',
            'phone' => '+966555000333',
            'brand_color' => '#1F7A4D',
        ]);
        $store->forceFill(['is_published' => true, 'published_at' => now()])->save();

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $store->id,
            'order_pickup' => false,
            'order_dine_in' => false,
            'order_delivery' => true,
            'order_curbside' => false,
            'delivery_pricing_mode' => 'per_km',
            'delivery_base_fee' => 5,
            'delivery_fee_per_km' => 1.5,
            'delivery_fee' => 10,
            'delivery_min_order' => 30,
            'delivery_max_distance_km' => 25,
            'default_prep_minutes' => 30,
            'customer_notes' => true,
            'tax_enabled' => false,
            'payment_required' => false,
            'deposit_required' => false,
        ]));

        $branch = Branch::create([
            'store_id' => $store->id,
            'name_ar' => 'سوق البركة — الملقا',
            'name_en' => 'Baraka Market — Al Malqa',
            'address_line' => 'حي الملقا، الرياض',
            'city' => 'الرياض',
            'latitude' => 24.8120,
            'longitude' => 46.6110,
            'slot_interval_minutes' => 15,
        ]);
        foreach (range(0, 6) as $day) {
            $branch->schedules()->create([
                'day_of_week' => $day,
                'opens_at' => '07:00',
                'closes_at' => '23:59',
                'is_closed' => false,
            ]);
        }

        $this->seedCatalog($store);
        app(QrCodeService::class)->generate($store);

        app(TenantContext::class)->setTenant(null);
    }

    private function seedCatalog(Store $store): void
    {
        $categories = [
            'produce' => ['خضار وفواكه', 'Fruits & Vegetables', 1],
            'dairy' => ['ألبان وبيض', 'Dairy & Eggs', 2],
            'bakery' => ['مخبوزات', 'Bakery', 3],
            'snacks' => ['سناكات', 'Snacks', 4],
            'drinks' => ['مشروبات', 'Beverages', 5],
            'household' => ['منظفات ومنزل', 'Household', 6],
        ];

        // [ar, en, category, price, compare_at, unit, stock, featured]
        $items = [
            ['موز', 'Fresh Bananas', 'produce', 5.95, 6.95, '1 كجم', 120, true],
            ['طماطم', 'Tomatoes', 'produce', 4.50, null, '1 كجم', 80, false],
            ['خيار', 'Cucumbers', 'produce', 3.95, null, '1 كجم', 90, false],
            ['ليمون', 'Lemons', 'produce', 7.50, 8.95, '1 كجم', 60, false],
            ['تفاح أحمر', 'Red Apples', 'produce', 8.95, null, '1 كجم', 70, true],
            ['حليب طازج', 'Fresh Milk', 'dairy', 6.25, 7.50, '1 لتر', 50, true],
            ['بيض بلدي', 'Brown Eggs', 'dairy', 17.95, 19.95, '12 حبة', 40, true],
            ['لبن', 'Laban', 'dairy', 5.50, null, '1 لتر', 45, false],
            ['جبن شرائح', 'Cheese Slices', 'dairy', 12.95, null, '200 جم', 30, false],
            ['خبز تميس', 'Tamees Bread', 'bakery', 3.00, null, '1 حبة', 25, false],
            ['توست أبيض', 'White Toast', 'bakery', 6.95, null, '600 جم', 35, false],
            ['كرواسون زبدة', 'Butter Croissant', 'bakery', 9.95, 11.95, '4 حبات', 20, true],
            ['شيبس ملح', 'Salted Chips', 'snacks', 4.25, null, '150 جم', 100, false],
            ['بسكويت شاي', 'Tea Biscuits', 'snacks', 5.95, null, '300 جم', 60, false],
            ['مكسرات مشكلة', 'Mixed Nuts', 'snacks', 24.95, 29.95, '400 جم', 25, true],
            ['ماء', 'Water', 'drinks', 9.95, null, '12 × 330 مل', 200, false],
            ['عصير برتقال', 'Orange Juice', 'drinks', 8.50, 9.95, '1 لتر', 40, false],
            ['قهوة عربية جاهزة', 'Arabic Coffee', 'drinks', 14.95, null, '500 مل', 30, false],
            ['صابون أطباق', 'Dish Soap', 'household', 11.95, null, '1 لتر', 40, false],
            ['مناديل', 'Tissues', 'household', 16.95, 19.95, '6 علب', 50, false],
            ['أكياس قمامة', 'Trash Bags', 'household', 12.50, null, '30 كيس', 35, false],
        ];

        $catId = [];
        foreach ($categories as $key => [$ar, $en, $sort]) {
            $catId[$key] = MenuCategory::create([
                'store_id' => $store->id, 'name_ar' => $ar, 'name_en' => $en, 'sort_order' => $sort,
            ])->id;
        }

        foreach ($items as $i => [$ar, $en, $cat, $price, $wasPrice, $unit, $stock, $featured]) {
            MenuItem::create([
                'store_id' => $store->id,
                'menu_category_id' => $catId[$cat],
                'name_ar' => $ar,
                'name_en' => $en,
                'price' => $price,
                'compare_at_price' => $wasPrice,
                'unit' => $unit,
                'stock_quantity' => $stock,
                'is_featured' => $featured,
                'is_available' => true,
                'is_active' => true,
                'sort_order' => $i,
            ]);
        }
    }
}
