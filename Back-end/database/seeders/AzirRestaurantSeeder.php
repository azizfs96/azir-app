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
 * AZIR — the restaurant demo store, seeded complete so a fresh deployment has
 * it ready without re-entering anything (spec: production seed).
 *
 * Includes: the merchant + owner, the store with its logo and banner, the full
 * VAT / ZATCA invoicing settings, the fulfilment configuration, and the whole
 * menu (6 categories, 11 dishes) with their images. Images are copied from
 * database/seeders/assets/azir into the public disk, so the seed is
 * self-contained (no external upload step).
 *
 * The owner password comes from SEED_OWNER_PASSWORD (default 'password') — set
 * it in the server .env and change it after the first login.
 * ============================================================================
 */
class AzirRestaurantSeeder extends Seeder
{
    /** @var array<string> assets under database/seeders/assets/azir */
    private const ASSETS = __DIR__.'/assets/azir';

    public function run(): void
    {
        $password = env('SEED_OWNER_PASSWORD', 'password');

        // Created directly (not via factory) so the seeder runs on a production
        // install where faker (a dev dependency) is absent.
        $owner = new User;
        $owner->forceFill([
            'name' => 'Azir Owner',
            'email' => 'owner@azir.sa',
            'password' => $password, // hashed by the model's cast
            'role' => User::ROLE_MERCHANT_OWNER,
            'phone' => '+966555000111',
            'locale' => 'ar',
            'is_active' => true,
            'email_verified_at' => now(),
            'phone_verified_at' => now(),
        ])->save();

        $merchant = Merchant::create([
            'owner_user_id' => $owner->id,
            'legal_name' => 'مؤسسة برجر البلد التجارية',
            'display_name' => 'برجر بلد',
            'contact_phone' => '+966555000111',
            'contact_email' => 'owner@azir.sa',
            'status' => Merchant::STATUS_APPROVED,
            'onboarding_step' => Merchant::FINAL_ONBOARDING_STEP,
        ]);
        $merchant->forceFill(['onboarded_at' => now(), 'approved_at' => now()])->save();
        $owner->forceFill(['merchant_id' => $merchant->id])->save();

        app(TenantContext::class)->setTenant($merchant);

        $store = Store::create([
            'merchant_id' => $merchant->id,
            // FIXED public token: the QR is printed and must NEVER change across
            // re-seeds/redeploys. Overridable via AZIR_STORE_TOKEN. (In
            // production, do not run migrate:fresh — but even if you do, the
            // token — and therefore the printed QR — stays the same.)
            'public_token' => env('AZIR_STORE_TOKEN', 'AZIR0001'),
            'name_ar' => 'برجر بلد',
            'name_en' => 'Balad Burger',
            'description_ar' => 'مطعم برجر ومشاوٍ',
            'description_en' => 'Burgers & grills',
            'business_type' => 'restaurant',
            'gender_policy' => 'all',
            'phone' => '+966555000111',
            'brand_color' => '#111111',
        ]);
        $store->forceFill(['is_published' => true, 'published_at' => now()])->save();

        // Branding: the merchant's logo + the storefront banner.
        $store->forceFill([
            'logo_path' => $this->copyAsset('logo.png', $store->id, 'logo'),
            'cover_path' => $this->copyAsset('banner.jpg', $store->id, 'cover'),
        ])->save();

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $store->id,
            // Fulfilment (all channels on) + merchant-controlled delivery fee.
            'order_pickup' => true,
            'order_dine_in' => true,
            'order_delivery' => true,
            'order_curbside' => true,
            'delivery_fee' => 15,
            'default_prep_minutes' => 20,
            'customer_notes' => true,
            // VAT / ZATCA e-invoicing.
            'tax_enabled' => true,
            'tax_rate' => 15,
            'tax_number' => '300000000000003',
            'legal_name' => 'مؤسسة برجر البلد التجارية',
            'national_address' => 'الرياض - حي قرطبة 12345',
            'commercial_registration' => '2052101911',
            'payment_required' => false,
            'deposit_required' => false,
        ]));

        Branch::create([
            'store_id' => $store->id,
            'name_ar' => 'مطعم البلد',
            'name_en' => 'Balad Restaurant',
            'address_line' => 'حي قرطبة، الرياض',
            'city' => 'الرياض',
            'slot_interval_minutes' => 15,
        ]);

        $this->seedMenu($store);

        app(QrCodeService::class)->generate($store);

        app(TenantContext::class)->setTenant(null);
    }

    private function seedMenu(Store $store): void
    {
        // category key => [ar, en, sort]
        $categories = [
            'burgers' => ['البرجر', 'Burgers', 0],
            'chicken' => ['الدجاج', 'Chicken', 1],
            'salads' => ['السلطات', 'Salads', 2],
            'sides' => ['المقبلات', 'Sides', 3],
            'drinks' => ['المشروبات', 'Drinks', 4],
            'desserts' => ['الحلى', 'Desserts', 5],
        ];

        $catId = [];
        foreach ($categories as $key => [$ar, $en, $sort]) {
            $catId[$key] = MenuCategory::create([
                'store_id' => $store->id, 'name_ar' => $ar, 'name_en' => $en, 'sort_order' => $sort,
            ])->id;
        }

        // [ar, en, category, price, calories, featured, image file]
        $items = [
            ['جمرة كلاسك', 'Jamra Classic', 'burgers', 34, 540, true, 'menu/jamra-classic.jpg'],
            ['سموكي باربكيو', 'Smoky BBQ', 'burgers', 39, 620, true, 'menu/smoky-bbq.jpg'],
            ['ترافل مشروم', 'Truffle Mushroom', 'burgers', 44, 660, false, 'menu/truffle-mushroom.jpg'],
            ['دجاج مقرمش', 'Crispy Chicken', 'chicken', 32, 580, true, 'menu/crispy-chicken.jpg'],
            ['شيش طاووق', 'Shish Tawook', 'chicken', 36, 480, false, 'menu/shish-tawook.jpg'],
            ['راب شاورما', 'Shawarma Wrap', 'chicken', 29, 510, false, 'menu/shawarma-wrap.jpg'],
            ['سلطة الجمرة', 'Jamra Salad', 'salads', 27, 220, false, 'menu/jamra-salad.jpg'],
            ['بطاطس بالتوابل', 'Spicy Fries', 'sides', 16, 340, true, 'menu/spicy-fries.jpg'],
            ['ميلك شيك', 'Milkshake', 'drinks', 19, 430, false, 'menu/milkshake.jpg'],
            ['ليمون بالنعناع', 'Mint Lemonade', 'drinks', 14, 120, false, 'menu/mint-lemonade.jpg'],
            ['سنديه كراميل', 'Caramel Sundae', 'desserts', 22, 390, true, 'menu/caramel-sundae.jpg'],
        ];

        foreach ($items as [$ar, $en, $cat, $price, $cal, $featured, $image]) {
            MenuItem::create([
                'store_id' => $store->id,
                'menu_category_id' => $catId[$cat],
                'name_ar' => $ar,
                'name_en' => $en,
                'price' => $price,
                'calories' => $cal,
                'is_featured' => $featured,
                'is_available' => true,
                'is_active' => true,
                'image_path' => $this->copyMenuAsset($image, $store->id),
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
