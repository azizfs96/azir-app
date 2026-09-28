<?php

namespace App\Domain\Discovery;

use App\Models\Customer;
use App\Models\CustomerStore;
use App\Models\QrScan;
use App\Models\Store;
use App\Support\TokenGenerator;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * ============================================================================
 * QR -> WASLA -> MERCHANT (spec §6, §46)
 *
 *   Scan QR
 *     -> resolve merchant/store
 *     -> if already in My Stores: open it
 *     -> if new: add to My Stores, then open it
 *
 * This class is the ONLY way a store ever enters a customer's world. There is
 * no search, no browse, no nearby, no recommendations. A store appears in
 * My Stores because the customer physically scanned a code or opened that
 * merchant's link — never because Wasla suggested it.
 * ============================================================================
 */
class StoreResolver
{
    /**
     * Find a published store by its public token.
     *
     * Returns null for unknown, unpublished, or suspended-merchant stores — all
     * three look identical from outside, so a scanner cannot tell an invalid
     * code from a deactivated business.
     */
    public function resolve(string $token): ?Store
    {
        $token = TokenGenerator::normalize($token);

        if ($token === '') {
            return null;
        }

        $store = Store::query()
            ->where('public_token', $token)
            ->with([
                'merchant',
                'bookingSettings',
                'activeBranches',
                'serviceCategories' => fn ($q) => $q->where('is_active', true)->orderBy('sort_order'),
                'serviceCategories.services' => fn ($q) => $q->where('is_active', true)->orderBy('sort_order'),
                'services' => fn ($q) => $q->where('is_active', true)->orderBy('sort_order'),
                'staff' => fn ($q) => $q->where('is_active', true)->where('is_bookable', true)->orderBy('sort_order'),
            ])
            ->first();

        if ($store === null || ! $store->isReachable()) {
            return null;
        }

        return $store;
    }

    /**
     * Record the scan (spec §25) and, when the customer is signed in, make sure
     * the store is in their My Stores list.
     */
    public function recordAccess(Store $store, Request $request, ?Customer $customer = null): void
    {
        DB::transaction(function () use ($store, $request, $customer): void {
            $isFirst = false;

            if ($customer !== null) {
                $isFirst = $this->addToMyStores($store, $customer);
            }

            /*
             * merchant_id is set with forceFill, not mass assignment.
             *
             * This runs on an UNAUTHENTICATED public request, so there is no
             * tenant context for BelongsToTenant to auto-fill from — and
             * merchant_id is deliberately absent from every model's $fillable
             * so no request payload can ever set it. Here it is derived from
             * the resolved store, which is trusted server-side data.
             */
            (new QrScan)->forceFill([
                'merchant_id' => $store->merchant_id,
                'store_id' => $store->id,
                'customer_id' => $customer?->id,
                'session_id' => $request->header('X-Session-Id'),
                // Hashed, never raw: analytics needs "same visitor?", not an address.
                'ip_hash' => $request->ip() !== null ? hash('sha256', $request->ip()) : null,
                'user_agent' => substr((string) $request->userAgent(), 0, 512),
                'platform' => $this->detectPlatform($request),
                'is_first_scan_for_customer' => $isFirst,
                'scanned_at' => CarbonImmutable::now(),
            ])->save();

            $store->qrCode?->increment('scan_count');
            $store->qrCode?->forceFill(['last_scanned_at' => CarbonImmutable::now()])->save();
        });
    }

    /**
     * Add the store to My Stores, or touch last_visited_at if already there.
     *
     * Returns true when this was the customer's FIRST encounter with the store —
     * the moment worth measuring in the QR funnel (spec §25).
     */
    public function addToMyStores(Store $store, Customer $customer, string $via = 'qr'): bool
    {
        $existing = CustomerStore::query()
            ->where('customer_id', $customer->id)
            ->where('store_id', $store->id)
            ->first();

        if ($existing !== null) {
            $existing->forceFill([
                'last_visited_at' => CarbonImmutable::now(),
                // Re-scanning a store the customer had hidden brings it back.
                'is_hidden' => false,
            ])->save();

            return false;
        }

        CustomerStore::create([
            'customer_id' => $customer->id,
            'store_id' => $store->id,
            'added_via' => $via,
            'first_added_at' => CarbonImmutable::now(),
            'last_visited_at' => CarbonImmutable::now(),
        ]);

        return true;
    }

    private function detectPlatform(Request $request): ?string
    {
        $agent = strtolower((string) $request->userAgent());

        return match (true) {
            str_contains($agent, 'iphone'), str_contains($agent, 'ipad'), str_contains($agent, 'ios') => 'ios',
            str_contains($agent, 'android') => 'android',
            $agent !== '' => 'web',
            default => null,
        };
    }
}
