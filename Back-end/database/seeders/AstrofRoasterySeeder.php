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
use Illuminate\Support\Facades\Storage;

/**
 * ============================================================================
 * ASTROF (استروف) — a specialty-coffee roastery, seeded complete: the merchant +
 * owner, the store with its logo and banner, the fulfilment configuration, and
 * the whole menu (5 categories, 56 items) with their images. Images are copied
 * from database/seeders/assets/astrof into the public disk (self-contained).
 *
 * VAT is OFF by default — the merchant enters their ZATCA details in the
 * dashboard before enabling it, so no placeholder tax number is seeded.
 * ============================================================================
 */
class AstrofRoasterySeeder extends Seeder
{
    private const ASSETS = __DIR__.'/assets/astrof';

    public function run(): void
    {
        $password = env('SEED_OWNER_PASSWORD', 'password');

        $owner = new User;
        $owner->forceFill([
            'name' => 'Astrof Owner',
            'email' => 'owner@astrof.sa',
            'password' => $password,
            'role' => User::ROLE_MERCHANT_OWNER,
            'phone' => '+966555000222',
            'locale' => 'ar',
            'is_active' => true,
            'email_verified_at' => now(),
            'phone_verified_at' => now(),
        ])->save();

        $merchant = Merchant::create([
            'owner_user_id' => $owner->id,
            'legal_name' => 'مؤسسة استروف للتحميص',
            'display_name' => 'استروف',
            'contact_phone' => '+966555000222',
            'contact_email' => 'owner@astrof.sa',
            'status' => Merchant::STATUS_APPROVED,
            'onboarding_step' => Merchant::FINAL_ONBOARDING_STEP,
        ]);
        $merchant->forceFill(['onboarded_at' => now(), 'approved_at' => now()])->save();
        $owner->forceFill(['merchant_id' => $merchant->id])->save();

        app(TenantContext::class)->setTenant($merchant);

        $store = Store::create([
            'merchant_id' => $merchant->id,
            // FIXED token (QR is printed): only store-alphabet chars (no 0 1 I L O U).
            'public_token' => env('ASTROF_STORE_TOKEN', 'ASTRFCAF'),
            'name_ar' => 'استروف',
            'name_en' => 'Astrof',
            'description_ar' => 'محمصة قهوة مختصة',
            'description_en' => 'Specialty coffee roastery',
            'business_type' => 'restaurant',
            'gender_policy' => 'all',
            'phone' => '+966555000222',
            'brand_color' => '#1A3A2B',
        ]);
        $store->forceFill(['is_published' => true, 'published_at' => now()])->save();

        $store->forceFill([
            'logo_path' => $this->copyAsset('logo.png', $store->id, 'logo'),
            'cover_path' => $this->copyAsset('banner.jpg', $store->id, 'cover'),
        ])->save();

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $store->id,
            'order_pickup' => true,
            'order_dine_in' => true,
            'order_delivery' => true,
            'order_curbside' => false,
            'delivery_fee' => 10,
            'default_prep_minutes' => 10,
            'customer_notes' => true,
            'tax_enabled' => false,
            'payment_required' => false,
            'deposit_required' => false,
        ]));

        $branch = Branch::create([
            'store_id' => $store->id,
            'name_ar' => 'استروف',
            'name_en' => 'Astrof',
            'address_line' => 'الرياض',
            'city' => 'الرياض',
            'latitude' => 24.7743,   // Al Olaya, Riyadh
            'longitude' => 46.6830,
            'slot_interval_minutes' => 15,
        ]);
        foreach (range(0, 6) as $day) {
            $branch->schedules()->create([
                'day_of_week' => $day,
                'opens_at' => '07:00',
                'closes_at' => '23:30',
                'is_closed' => false,
            ]);
        }

        $this->seedMenu($store);
        app(QrCodeService::class)->generate($store);
        app(TenantContext::class)->setTenant(null);
    }

    private function seedMenu(Store $store): void
    {
        // categories: key => [ar, en, sort]
        $categories = [
            'coffee-crops' => ['المحاصيل', 'Coffee Crops', 0],
            'hot-coffee' => ['القهوة الحارة', 'Hot Coffee', 1],
            'cold-coffee' => ['القهوة الباردة', 'Cold Coffee', 2],
            'other-drinks' => ['مشروبات أخرى', 'Other Drinks', 3],
            'desserts' => ['الحلا', 'Desserts', 4],
        ];
        // [ar, en, category, price, featured, image|null]
        $items = [
            ['محصول الفيفا 250 جرام', 'Al-Fifa Crop - 250G', 'coffee-crops', 92, false, 'menu/al-fifa-crop-250g.jpg'],
            ['محصول الفيفا 1 كيلو', 'Al-Fifa Crop - 1KG', 'coffee-crops', 368, false, 'menu/al-fifa-crop-1kg.jpg'],
            ['كسكاره بيور 1 كيلو', 'Pure Cascara - 1KG', 'coffee-crops', 97.75, false, null],
            ['محصول قهوه عربى (ارث) 250 جرام', 'Arabic Coffee Crop (Erth) - 250G', 'coffee-crops', 44, false, 'menu/arabic-coffee-crop-erth-250g.jpg'],
            ['بوكس الثروات', 'Country\'s Wealth Box', 'coffee-crops', 299, true, 'menu/country-s-wealth-box.jpg'],
            ['محصول ال يحي 1 كجم', 'Al Yahya Crop - 1KG', 'coffee-crops', 269, false, 'menu/al-yahya-crop-1kg.jpg'],
            ['محصول جبال الحشر 1 كجم', 'Gebal Al Hashr Crop - 1KG', 'coffee-crops', 349, false, 'menu/gebal-al-hashr-crop-1kg.jpg'],
            ['محصول العارضه 1 كجم', 'El-Arda Crop - 1KG', 'coffee-crops', 349, false, 'menu/el-arda-crop-1kg.jpg'],
            ['محصول العبدلى 1 كجم', 'Al-Abdali Crop - 1KG', 'coffee-crops', 620, false, 'menu/al-abdali-crop-1kg.jpg'],
            ['محصول ال سعيد 1 كجم', 'Al Saeed Crop - 1KG', 'coffee-crops', 469, false, 'menu/al-saeed-crop-1kg.jpg'],
            ['محصول العبدلي 250 جرام', 'Al-Abdali Crop - 250G', 'coffee-crops', 171, false, 'menu/al-abdali-crop-250g.jpg'],
            ['محصول ال يحيى 250 جرام', 'Al Yahya Crop - 250G', 'coffee-crops', 69, false, 'menu/al-yahya-crop-250g.jpg'],
            ['محصول العارضة 250 جرام', 'El-Arda Crop - 250G', 'coffee-crops', 89, false, 'menu/el-arda-crop-250g.jpg'],
            ['محصول ال سعيد 250 جرام', 'Al Saeed Crop - 250G', 'coffee-crops', 118, false, 'menu/al-saeed-crop-250g.jpg'],
            ['محصول جبال الحشر 250 جرام', 'Gebal Al Hashr Crop - 250G', 'coffee-crops', 89, false, 'menu/gebal-al-hashr-crop-250g.jpg'],
            ['محصول الفيفا حار', 'Al-Fifa Hot', 'hot-coffee', 19, false, 'menu/al-fifa-hot.jpg'],
            ['اسبرسو الفيفا', 'Espresso Al-Fifa', 'hot-coffee', 14, false, 'menu/espresso-al-fifa.jpg'],
            ['اسبريسو جبال الحشر', 'Espresso Gebal Al Hashr', 'hot-coffee', 16, false, 'menu/espresso-gebal-al-hashr.jpg'],
            ['امركانو حار', 'Americano Hot', 'hot-coffee', 13, false, 'menu/americano-hot.jpg'],
            ['اسبريسو ال سعيد', 'Espresso Al Saeed', 'hot-coffee', 17, false, 'menu/espresso-al-saeed.jpg'],
            ['اسبريسو العارضة', 'Espresso El Arda', 'hot-coffee', 16, false, 'menu/espresso-el-arda.jpg'],
            ['ال يحيى حار', 'Al Yahya Hot', 'hot-coffee', 17, false, 'menu/al-yahya-hot.jpg'],
            ['قهوة اليوم حار', 'Hot Coffee Of The Day', 'hot-coffee', 10, false, 'menu/hot-coffee-of-the-day.jpg'],
            ['اسبريسو ال يحيى', 'Espresso Al Yahya', 'hot-coffee', 12, false, 'menu/espresso-al-yahya.jpg'],
            ['كورتادو', 'Cortado', 'hot-coffee', 15, false, 'menu/cortado.jpg'],
            ['كابتشينو', 'Cappuccino', 'hot-coffee', 18, true, 'menu/cappuccino.jpg'],
            ['فلات وايت', 'Flat White', 'hot-coffee', 17, false, 'menu/flat-white.jpg'],
            ['لاتيه', 'Latte', 'hot-coffee', 18, true, 'menu/latte.jpg'],
            ['اسبريسو الجمعة (العبدلي)', 'Espresso Friday (Al-Abdali)', 'hot-coffee', 19, false, 'menu/espresso-friday-al-abdali.jpg'],
            ['جبال الحشر حار', 'Gebal Al-Hashr Hot', 'hot-coffee', 19, false, 'menu/gebal-al-hashr-hot.jpg'],
            ['ال سعيد حار', 'Al Saeed Hot', 'hot-coffee', 22, false, 'menu/al-saeed-hot.jpg'],
            ['العارضة الحار', 'El Arda Hot', 'hot-coffee', 19, false, 'menu/el-arda-hot.jpg'],
            ['العبدلي حار (الجمعة)', 'Al-Abdali Hot (Friday)', 'hot-coffee', 23, false, 'menu/al-abdali-hot-friday.jpg'],
            ['محصول الفيفا بارد', 'Al-Fifa Cold', 'cold-coffee', 21, false, 'menu/al-fifa-cold.jpg'],
            ['ألفريدو', 'Alfredo', 'cold-coffee', 14, false, 'menu/alfredo.jpg'],
            ['اميركانو بارد', 'Americano Cold', 'cold-coffee', 14, false, 'menu/americano-cold.jpg'],
            ['ال يحيى بارد', 'Al Yahya Cold', 'cold-coffee', 19, false, 'menu/al-yahya-cold.jpg'],
            ['قهوة اليوم بارد', 'Iced Coffee Of The Day', 'cold-coffee', 12, false, 'menu/iced-coffee-of-the-day.jpg'],
            ['لاتيه بارد', 'Iced Latte', 'cold-coffee', 18, false, 'menu/iced-latte.jpg'],
            ['جبال الحشر بارد', 'Gebal Al Hashr Cold', 'cold-coffee', 21, false, 'menu/gebal-al-hashr-cold.jpg'],
            ['ال سعيد بارد', 'Al Saeed Cold', 'cold-coffee', 23, false, 'menu/al-saeed-cold.jpg'],
            ['العبدلي بارد (الجمعة)', 'Al-Abdali Cold (Friday)', 'cold-coffee', 25, false, 'menu/al-abdali-cold-friday.jpg'],
            ['العارضة بارد', 'El Arda Cold', 'cold-coffee', 21, false, 'menu/el-arda-cold.jpg'],
            ['كسكارا', 'Cascara', 'other-drinks', 20, false, 'menu/cascara.jpg'],
            ['كركديه بارد', 'Cold Hibiscus', 'other-drinks', 20, false, 'menu/cold-hibiscus.jpg'],
            ['ايس تى شمام', 'Ice Tea Melon', 'other-drinks', 17, false, 'menu/ice-tea-melon.jpg'],
            ['هوت شوكلاته كلاسيك', 'Classic Hot Chocolate', 'other-drinks', 20, false, null],
            ['هوت شوكلات بالكريمة', 'Hot Chocolate With Cream', 'other-drinks', 22, false, null],
            ['ماتشا بارد', 'Cold Matcha', 'other-drinks', 21, false, 'menu/cold-matcha.jpg'],
            ['كرانشى تشوكلت', 'Crunchy Chocolate', 'desserts', 26, false, 'menu/crunchy-chocolate.jpg'],
            ['كراميل بيكان', 'Caramel Pecan', 'desserts', 24, false, 'menu/caramel-pecan.jpg'],
            ['سولتد كراميل', 'Salted Caramel', 'desserts', 9, true, 'menu/salted-caramel.jpg'],
            ['ويفر', 'Wafer', 'desserts', 9, false, null],
            ['شوكولاتة داكنة', 'Dark Chocolate', 'desserts', 9, false, null],
            ['بيكان كيك', 'Pecan Cake', 'desserts', 27, true, 'menu/pecan-cake.jpg'],
            ['سيريلاك كيك', 'Cerelac Cake', 'desserts', 28, false, 'menu/cerelac-cake.jpg'],
        ];

        $catId = [];
        foreach ($categories as $key => [$ar, $en, $sort]) {
            $catId[$key] = MenuCategory::create([
                'store_id' => $store->id, 'name_ar' => $ar, 'name_en' => $en, 'sort_order' => $sort,
            ])->id;
        }

        foreach ($items as [$ar, $en, $cat, $price, $featured, $image]) {
            MenuItem::create([
                'store_id' => $store->id,
                'menu_category_id' => $catId[$cat],
                'name_ar' => $ar,
                'name_en' => $en,
                'price' => $price,
                'is_featured' => $featured,
                'is_available' => true,
                'is_active' => true,
                'image_path' => $image ? $this->copyMenuAsset($image, $store->id) : null,
            ]);
        }
    }

    /** Copy a store-level asset (logo/cover) to the public disk; return its path. */
    private function copyAsset(string $file, int $storeId, string $kind): string
    {
        $ext = pathinfo($file, PATHINFO_EXTENSION);
        $path = "stores/{$storeId}/{$kind}.{$ext}";
        Storage::disk('public')->put($path, (string) file_get_contents(self::ASSETS."/{$file}"));

        return $path;
    }

    /** Copy a menu image to the public disk; return its path. */
    private function copyMenuAsset(string $file, int $storeId): string
    {
        $name = basename($file);
        $path = "stores/{$storeId}/menu/{$name}";
        Storage::disk('public')->put($path, (string) file_get_contents(self::ASSETS."/{$file}"));

        return $path;
    }
}
