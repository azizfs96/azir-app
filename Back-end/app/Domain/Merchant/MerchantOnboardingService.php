<?php

namespace App\Domain\Merchant;

use App\Domain\Discovery\QrCodeService;
use App\Models\Booking;
use App\Models\BookingSettings;
use App\Models\Merchant;
use App\Models\Store;
use App\Models\User;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/**
 * ============================================================================
 * MERCHANT ONBOARDING (spec §11, §42)
 *
 *   1 Business info   4 Services         7 Payment settings
 *   2 Business type   5 Staff (optional) 8 Generate QR
 *   3 Branch          6 Booking settings 9 Publish
 *
 * "The merchant should be able to become operational quickly. Do not expose 50
 *  technical settings during onboarding."
 *
 * So registration creates the store, booking settings and QR up front with
 * sensible defaults. A salon owner can reach a working QR with nothing but a
 * name, a branch and one service — every other step is skippable and every
 * advanced option lives under Settings.
 * ============================================================================
 */
class MerchantOnboardingService
{
    public function __construct(
        private readonly QrCodeService $qr,
        private readonly TenantContext $tenant,
    ) {}

    /**
     * Register a business and its owner.
     *
     * @param  array<string, mixed>  $data
     */
    public function register(array $data): Merchant
    {
        return DB::transaction(function () use ($data): Merchant {
            $owner = User::create([
                'name' => $data['owner_name'],
                'email' => strtolower($data['email']),
                'phone' => $data['phone'],
                'password' => Hash::make($data['password']),
                'role' => User::ROLE_MERCHANT_OWNER,
                'locale' => $data['locale'] ?? 'ar',
            ]);

            $merchant = Merchant::create([
                'owner_user_id' => $owner->id,
                'legal_name' => $data['business_name'],
                'display_name' => $data['business_name'],
                'contact_phone' => $data['phone'],
                'contact_email' => strtolower($data['email']),
                // Every merchant starts pending; an admin approves (spec §39).
                'status' => Merchant::STATUS_PENDING,
                'onboarding_step' => 2,
            ]);

            $owner->forceFill(['merchant_id' => $merchant->id])->save();

            // The tenant must exist before any tenant-owned row is created.
            $this->tenant->setTenant($merchant);

            $store = Store::create([
                'name_ar' => $data['business_name'],
                'name_en' => $data['business_name_en'] ?? null,
                'business_type' => $data['business_type'] ?? config('wasla.default_engine'),
                'phone' => $data['phone'],
            ]);

            /*
             * Booking settings and the QR are created NOW, not at step 6/8.
             *
             * The merchant can change settings later, but the store is
             * structurally complete from the first minute — which is what makes
             * "add one service and publish" a viable path (spec §11).
             */
            BookingSettings::create(array_merge(
                BookingSettings::defaults(),
                ['store_id' => $store->id],
            ));

            $this->qr->generate($store);

            return $merchant->load('store');
        });
    }

    /**
     * Record progress through the wizard so a drop-off resumes where it left off.
     */
    public function advanceTo(Merchant $merchant, int $step): Merchant
    {
        // Never move backwards: revisiting step 3 to edit a branch should not
        // undo the fact that services were already added.
        if ($step > $merchant->onboarding_step) {
            $merchant->forceFill(['onboarding_step' => min($step, Merchant::FINAL_ONBOARDING_STEP)])->save();
        }

        return $merchant;
    }

    /**
     * What still blocks going live (spec §42).
     *
     * Deliberately short. These are the only things a store genuinely cannot
     * function without — everything else has a working default.
     *
     * @return array<int, string>
     */
    public function blockersFor(Store $store): array
    {
        $blockers = [];

        if ($store->activeBranches()->count() === 0) {
            $blockers[] = 'branch_required';
        }

        if ($store->services()->where('is_active', true)->count() === 0) {
            $blockers[] = 'service_required';
        }

        // A branch with no opening hours would produce zero bookable slots —
        // a store that looks live but can never be booked.
        $hasHours = $store->activeBranches()
            ->whereHas('schedules', fn ($q) => $q->where('is_closed', false))
            ->exists();

        if (! $hasHours && $blockers === []) {
            $blockers[] = 'working_hours_required';
        }

        return $blockers;
    }

    /**
     * Go live (step 9).
     *
     * @return array{published: bool, blockers: array<int, string>}
     */
    public function publish(Store $store): array
    {
        $blockers = $this->blockersFor($store);

        if ($blockers !== []) {
            return ['published' => false, 'blockers' => $blockers];
        }

        $store->forceFill([
            'is_published' => true,
            'published_at' => CarbonImmutable::now(),
        ])->save();

        $merchant = $store->merchant;

        $merchant->forceFill([
            'onboarding_step' => Merchant::FINAL_ONBOARDING_STEP,
            'onboarded_at' => $merchant->onboarded_at ?? CarbonImmutable::now(),
        ])->save();

        return ['published' => true, 'blockers' => []];
    }

    /**
     * Today's figures for the dashboard (spec §13).
     *
     * @return array<string, mixed>
     */
    public function dashboardFor(Store $store): array
    {
        $timezone = $store->timezone;
        $now = CarbonImmutable::now($timezone);
        $dayStart = $now->startOfDay()->utc();
        $dayEnd = $now->endOfDay()->utc();

        // One grouped query rather than six counts.
        $byStatus = Booking::query()
            ->where('store_id', $store->id)
            ->whereBetween('starts_at', [$dayStart, $dayEnd])
            ->selectRaw('booking_status, COUNT(*) as total, SUM(price) as revenue')
            ->groupBy('booking_status')
            ->get()
            ->keyBy('booking_status');

        $count = fn (string $status) => (int) ($byStatus[$status]->total ?? 0);

        /*
         * Revenue counts COMPLETED bookings only.
         *
         * Not confirmed ones — a confirmed appointment is a promise, not money.
         * Counting it early would make the number drop whenever someone
         * cancels, which reads as a bug to the merchant.
         */
        $revenue = (float) ($byStatus['completed']->revenue ?? 0);

        return [
            'date' => $now->format('Y-m-d'),
            'timezone' => $timezone,
            'today' => [
                'total' => array_sum(array_map($count, [
                    'pending', 'confirmed', 'checked_in', 'completed', 'cancelled', 'no_show',
                ])),
                'pending' => $count('pending'),
                'confirmed' => $count('confirmed'),
                'checked_in' => $count('checked_in'),
                'completed' => $count('completed'),
                'cancelled' => $count('cancelled'),
                'no_show' => $count('no_show'),
            ],
            'revenue' => [
                'amount' => $revenue,
                'currency' => $store->currency,
                'basis' => 'completed_bookings',
            ],
        ];
    }
}
