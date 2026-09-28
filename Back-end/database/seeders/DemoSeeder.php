<?php

namespace Database\Seeders;

use App\Domain\Discovery\QrCodeService;
use App\Models\Branch;
use App\Models\BookingSettings;
use App\Models\Merchant;
use App\Models\Service;
use App\Models\ServiceCategory;
use App\Models\Staff;
use App\Models\Store;
use App\Models\User;
use App\Support\TenantContext;
use Illuminate\Database\Seeder;

/**
 * The spec §42 worked example, as runnable data.
 *
 *   Business:  Glow Beauty        Services: Hair Cut  100 SAR / 30 min
 *   Branch:    Olaya                        Hair Color 250 SAR / 120 min
 *   Staff:     Sara, Reem                   Facial     180 SAR / 60 min
 *   Booking:   staff selection = YES, cancellation = YES, rescheduling = YES
 *
 * A second merchant (ABC Spa) is seeded with the OPPOSITE configuration — no
 * staff selection, multiple branches — so the configurable booking engine can
 * be seen doing two different things from one codebase (spec §9).
 */
class DemoSeeder extends Seeder
{
    public function run(): void
    {
        $this->seedGlowBeauty();
        $this->seedAbcSpa();
        $this->seedAdmin();
    }

    /**
     * Merchant A — exposes staff selection, one branch (spec §9 Merchant A).
     */
    private function seedGlowBeauty(): void
    {
        $owner = User::factory()->create([
            'name' => 'Glow Beauty Owner',
            'email' => 'owner@glow.sa',
            'password' => 'password',
            'role' => User::ROLE_MERCHANT_OWNER,
            'phone' => '+966501110001',
        ]);

        $merchant = Merchant::create([
            'owner_user_id' => $owner->id,
            'legal_name' => 'Glow Beauty Trading Est.',
            'display_name' => 'Glow Beauty',
            'contact_phone' => '+966501110001',
            'contact_email' => 'owner@glow.sa',
            'status' => Merchant::STATUS_APPROVED,
            'onboarding_step' => Merchant::FINAL_ONBOARDING_STEP,
        ]);

        $merchant->forceFill(['onboarded_at' => now(), 'approved_at' => now()])->save();
        $owner->forceFill(['merchant_id' => $merchant->id])->save();

        app(TenantContext::class)->setTenant($merchant);

        $store = Store::create([
            'merchant_id' => $merchant->id,
            'name_ar' => 'جلو بيوتي',
            'name_en' => 'Glow Beauty',
            'description_ar' => 'صالون تجميل نسائي في العليا',
            'description_en' => 'Ladies beauty salon in Olaya',
            'business_type' => 'beauty_wellness',
            'gender_policy' => 'women_only',
            'phone' => '+966501110001',
            'brand_color' => '#B76E79',
        ]);

        $store->forceFill(['is_published' => true, 'published_at' => now()])->save();

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $store->id,
            // The §42 configuration.
            'staff_selection' => true,
            'allow_cancellation' => true,
            'allow_rescheduling' => true,
            'customer_notes' => true,
            // Deposit stays off: online payment is out of scope for the MVP.
            'deposit_required' => false,
            'payment_required' => false,
        ]));

        $branch = Branch::create([
            'store_id' => $store->id,
            'name_ar' => 'العليا',
            'name_en' => 'Olaya',
            'address_line' => 'Olaya Street, Riyadh',
            'city' => 'Riyadh',
            'slot_interval_minutes' => 15,
        ]);

        $this->weeklyHours($branch, '10:00', '22:00');

        $hair = ServiceCategory::create([
            'store_id' => $store->id, 'name_ar' => 'الشعر', 'name_en' => 'Hair', 'sort_order' => 1,
        ]);
        $face = ServiceCategory::create([
            'store_id' => $store->id, 'name_ar' => 'البشرة', 'name_en' => 'Facial', 'sort_order' => 2,
        ]);

        foreach ([
            ['قص شعر', 'Hair Cut', 100, 30, $hair],
            ['صبغة شعر', 'Hair Color', 250, 120, $hair],
            ['تنظيف بشرة', 'Facial', 180, 60, $face],
        ] as [$ar, $en, $price, $minutes, $category]) {
            Service::create([
                'store_id' => $store->id,
                'service_category_id' => $category->id,
                'name_ar' => $ar,
                'name_en' => $en,
                'price' => $price,
                'duration_minutes' => $minutes,
            ]);
        }

        foreach (['Sara', 'Reem'] as $index => $name) {
            $staff = Staff::create([
                'store_id' => $store->id,
                'branch_id' => $branch->id,
                'name' => $name,
                'title_ar' => 'مصففة',
                'title_en' => 'Stylist',
                'gender' => 'female',
                'sort_order' => $index,
            ]);

            // No staff_services rows on purpose: per spec §15 that means they
            // can perform every service, which is the zero-setup default.
            $this->staffHours($staff);
        }

        app(QrCodeService::class)->generate($store);

        $this->command?->info("Glow Beauty  -> {$store->deepLink()}");
    }

    /**
     * Merchant B — NO staff selection, two branches (spec §9 Merchant B).
     */
    private function seedAbcSpa(): void
    {
        $owner = User::factory()->create([
            'name' => 'ABC Spa Owner',
            'email' => 'owner@abcspa.sa',
            'password' => 'password',
            'role' => User::ROLE_MERCHANT_OWNER,
            'phone' => '+966502220002',
        ]);

        $merchant = Merchant::create([
            'owner_user_id' => $owner->id,
            'legal_name' => 'ABC Spa Co.',
            'display_name' => 'ABC Spa',
            'contact_phone' => '+966502220002',
            'status' => Merchant::STATUS_APPROVED,
            'onboarding_step' => Merchant::FINAL_ONBOARDING_STEP,
        ]);

        $merchant->forceFill(['onboarded_at' => now(), 'approved_at' => now()])->save();
        $owner->forceFill(['merchant_id' => $merchant->id])->save();

        app(TenantContext::class)->setTenant($merchant);

        $store = Store::create([
            'merchant_id' => $merchant->id,
            'name_ar' => 'إيه بي سي سبا',
            'name_en' => 'ABC Spa',
            'business_type' => 'beauty_wellness',
            'brand_color' => '#2E5E4E',
        ]);

        $store->forceFill(['is_published' => true, 'published_at' => now()])->save();

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $store->id,
            'staff_selection' => false,   // customers never choose a therapist
            'branch_selection' => true,   // ...but they do choose a branch
            'customer_notes' => false,
        ]));

        foreach ([['الملقا', 'Al Malqa'], ['النخيل', 'Al Nakheel']] as [$ar, $en]) {
            $branch = Branch::create([
                'store_id' => $store->id,
                'name_ar' => $ar,
                'name_en' => $en,
                'city' => 'Riyadh',
                'slot_interval_minutes' => 30,
                'buffer_after_minutes' => 15,
            ]);

            $this->weeklyHours($branch, '09:00', '21:00');

            // Therapists exist but are never shown; the engine assigns them.
            foreach (['Nora', 'Huda'] as $name) {
                $this->staffHours(Staff::create([
                    'store_id' => $store->id,
                    'branch_id' => $branch->id,
                    'name' => $name,
                    'gender' => 'female',
                ]), '09:00', '21:00');
            }
        }

        Service::create([
            'store_id' => $store->id,
            'name_ar' => 'مساج استرخائي',
            'name_en' => 'Relaxing Massage',
            'price' => 300,
            'duration_minutes' => 60,
        ]);

        app(QrCodeService::class)->generate($store);

        $this->command?->info("ABC Spa      -> {$store->deepLink()}");
    }

    private function seedAdmin(): void
    {
        User::factory()->create([
            'name' => 'Wasla Admin',
            'email' => 'admin@wasla.sa',
            'password' => 'password',
            'role' => User::ROLE_ADMIN,
            'phone' => '+966500000000',
            'merchant_id' => null,
        ]);
    }

    private function weeklyHours(Branch $branch, string $opens, string $closes): void
    {
        foreach (range(0, 6) as $day) {
            $branch->schedules()->create([
                'day_of_week' => $day, 'opens_at' => $opens, 'closes_at' => $closes,
            ]);
        }
    }

    private function staffHours(Staff $staff, string $start = '10:00', string $end = '22:00'): void
    {
        foreach (range(0, 6) as $day) {
            $staff->schedules()->create([
                'day_of_week' => $day,
                'starts_at' => $start,
                'ends_at' => $end,
                // A real break, so availability has something to carve out.
                'break_starts_at' => '14:00',
                'break_ends_at' => '15:00',
                // Friday morning off is the Saudi norm.
                'is_off' => $day === 5,
            ]);
        }
    }
}
