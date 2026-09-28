<?php

namespace Tests\Feature;

use App\Domain\Booking\BookingService;
use App\Domain\Booking\BookingStatus;
use App\Models\Booking;
use App\Models\BookingSettings;
use App\Models\Branch;
use App\Models\Merchant;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Cache;
use Tests\TestCase;

/**
 * ============================================================================
 * AVAILABILITY CACHE INVALIDATION (audit finding C-2)
 *
 * AvailabilityController caches slot lists for 60 seconds. Nothing used to
 * clear them, so for up to a minute after a booking the API kept advertising
 * the slot that had just been taken — every customer who tapped it received
 * 409 SLOT_TAKEN. At a busy salon that is not an edge case, it is the peak-hour
 * experience.
 *
 * The cache is a PERFORMANCE device, never the source of truth: the booking
 * transaction and its row lock remain authoritative. These tests assert the
 * cache tells the truth promptly AND that the write path still refuses a taken
 * slot even when the cache is stale.
 * ============================================================================
 */
class AvailabilityCacheTest extends TestCase
{
    use RefreshDatabase;

    protected const TZ = 'Asia/Riyadh';

    protected Store $store;

    protected Branch $branch;

    protected Staff $sara;

    protected Staff $reem;

    protected Service $haircut;

    protected function setUp(): void
    {
        parent::setUp();

        [$this->store, $this->branch, $this->sara, $this->reem, $this->haircut] =
            $this->seedStore('Glow Beauty');

        app(TenantContext::class)->setTenant(null);
    }

    /**
     * @return array{0: Store, 1: Branch, 2: Staff, 3: Staff, 4: Service}
     */
    protected function seedStore(string $name): array
    {
        $merchant = Merchant::factory()->create(['display_name' => $name]);
        app(TenantContext::class)->setTenant($merchant);

        $store = Store::factory()->create(['merchant_id' => $merchant->id, 'name_en' => $name]);

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $store->id,
            'min_lead_time_minutes' => 0,
            'max_advance_days' => 365,
            'staff_selection' => true,
        ]));

        $branch = Branch::factory()->forStore($store)->create(['slot_interval_minutes' => 30]);

        foreach (range(0, 6) as $day) {
            $branch->schedules()->create([
                'day_of_week' => $day, 'opens_at' => '09:00', 'closes_at' => '21:00',
            ]);
        }

        $staff = [];

        foreach (['Sara', 'Reem'] as $person) {
            $member = Staff::factory()->forStore($store)->create([
                'name' => $person, 'branch_id' => $branch->id,
            ]);

            foreach (range(0, 6) as $day) {
                $member->schedules()->create([
                    'day_of_week' => $day, 'starts_at' => '09:00', 'ends_at' => '21:00',
                ]);
            }

            $staff[] = $member;
        }

        $service = Service::factory()->forStore($store)->create([
            'name_en' => 'Hair Cut', 'duration_minutes' => 60,
            'buffer_after_minutes' => 0, 'price' => 100,
        ]);

        return [$store, $branch, $staff[0], $staff[1], $service];
    }

    protected function date(): string
    {
        return CarbonImmutable::now(self::TZ)->addDays(3)->format('Y-m-d');
    }

    /**
     * Read availability through the HTTP endpoint — which is where the cache
     * lives. Calling the engine directly would bypass the thing under test.
     *
     * @return array<int, string> local HH:MM start times
     */
    protected function times(?Staff $staff = null, ?string $date = null, ?Store $store = null): array
    {
        $store ??= $this->store;
        $service = $store->is($this->store)
            ? $this->haircut
            : Service::query()->withoutGlobalScopes()->where('store_id', $store->id)->firstOrFail();

        $query = http_build_query(array_filter([
            'service_id' => $service->id,
            'date' => $date ?? $this->date(),
            'staff_id' => $staff?->id,
        ]));

        return collect(
            $this->getJson("/api/v1/stores/{$store->public_token}/availability?{$query}")
                ->assertOk()
                ->json('days.0.slots')
        )->pluck('time')->all();
    }

    protected function bookAt(string $time, ?Staff $staff = null): Booking
    {
        $startsAt = CarbonImmutable::parse($this->date().' '.$time, self::TZ);

        return app(BookingService::class)->create(
            store: Store::query()->withoutGlobalScopes()->with('bookingSettings')->find($this->store->id),
            service: $this->haircut,
            startsAt: $startsAt,
            branch: $this->branch,
            requestedStaff: $staff ?? Staff::query()->withoutGlobalScopes()
                ->with(['schedules', 'services'])->find($this->sara->id),
        );
    }

    // =====================================================================
    // TEST 1 — a booking must remove the slot from the cached response
    // =====================================================================

    public function test_a_cached_slot_disappears_immediately_after_it_is_booked(): void
    {
        // 1. Prime the cache.
        $before = $this->times($this->sara);
        $this->assertContains('12:00', $before, 'Fixture problem: 12:00 should start out free.');

        // 2. Take that exact slot.
        $this->bookAt('12:00');

        // 3. Ask again. Without invalidation this is served from the 60-second
        //    cache and still advertises 12:00 — the bug this test exists for.
        $after = $this->times($this->sara);

        $this->assertNotContains(
            '12:00',
            $after,
            'The availability cache is still advertising a slot that was just booked.',
        );
    }

    // =====================================================================
    // TEST 2 — cancelling frees the slot again
    // =====================================================================

    public function test_cancelling_a_booking_returns_the_slot_to_availability(): void
    {
        $booking = $this->bookAt('13:00');

        $this->assertNotContains('13:00', $this->times($this->sara));

        // Cancelled bookings release their time (BookingStatus::blocksAvailability).
        $booking->transitionTo(BookingStatus::Cancelled, 'customer');

        $this->assertContains(
            '13:00',
            $this->times($this->sara),
            'A cancelled booking must free its slot in the cached response too.',
        );
    }

    // =====================================================================
    // TEST 3 — rescheduling frees the old slot and takes the new one
    // =====================================================================

    public function test_rescheduling_updates_both_the_old_and_the_new_slot(): void
    {
        $booking = $this->bookAt('14:00');

        $primed = $this->times($this->sara);
        $this->assertNotContains('14:00', $primed);
        $this->assertContains('16:00', $primed);

        app(BookingService::class)->reschedule(
            $booking,
            CarbonImmutable::parse($this->date().' 16:00', self::TZ),
            Staff::query()->withoutGlobalScopes()->with(['schedules', 'services'])->find($this->sara->id),
        );

        $after = $this->times($this->sara);

        $this->assertContains('14:00', $after, 'The vacated slot must become bookable again.');
        $this->assertNotContains('16:00', $after, 'The new slot must no longer be offered.');
    }

    // =====================================================================
    // TEST 4 — a rolled-back booking must not distort availability
    // =====================================================================

    public function test_a_failed_booking_leaves_availability_consistent(): void
    {
        $this->assertContains('15:00', $this->times($this->sara));

        // Force a failure INSIDE the transaction: the slot is already taken, so
        // BookingService throws and rolls back.
        $this->bookAt('15:00');

        try {
            $this->bookAt('15:00');
            $this->fail('The second booking should have been refused.');
        } catch (\App\Domain\Booking\Exceptions\SlotNoLongerAvailable) {
            // expected
        }

        // Exactly one booking exists, and availability agrees with the database.
        $this->assertSame(
            1,
            Booking::query()->withoutGlobalScopes()
                ->where('staff_id', $this->sara->id)
                ->whereIn('booking_status', BookingStatus::blockingValues())
                ->count(),
        );

        $this->assertNotContains('15:00', $this->times($this->sara));
    }

    // =====================================================================
    // TEST 5 — one merchant's writes must not disturb another's cache
    // =====================================================================

    public function test_invalidation_is_scoped_to_the_merchant(): void
    {
        [$otherStore, , $otherStaff] = $this->seedStore('ABC Spa');
        app(TenantContext::class)->setTenant(null);

        // Prime BOTH merchants.
        $this->assertContains('12:00', $this->times($this->sara));
        $otherBefore = $this->times($otherStaff, store: $otherStore);
        $this->assertContains('12:00', $otherBefore);

        // A booking at Glow Beauty.
        $this->bookAt('12:00');

        $this->assertNotContains('12:00', $this->times($this->sara));

        $this->assertSame(
            $otherBefore,
            $this->times($otherStaff, store: $otherStore),
            "One merchant's booking changed another merchant's availability.",
        );
    }

    // =====================================================================
    // TEST 6 — invalidation is scoped to the staff member who was booked
    // =====================================================================

    public function test_booking_one_staff_member_does_not_evict_another_staff_cache(): void
    {
        $saraBefore = $this->times($this->sara);
        $reemBefore = $this->times($this->reem);

        $this->assertContains('12:00', $saraBefore);
        $this->assertContains('12:00', $reemBefore);

        $this->bookAt('12:00', $this->sara);

        // Sara loses the slot; Reem is untouched and still free at 12:00.
        $this->assertNotContains('12:00', $this->times($this->sara));

        $this->assertSame(
            $reemBefore,
            $this->times($this->reem),
            "Booking Sara must not change Reem's availability.",
        );
    }

    // =====================================================================
    // The "any staff" aggregate must also stay honest
    // =====================================================================

    public function test_the_any_staff_view_reflects_a_booking_once_nobody_is_free(): void
    {
        // Only Sara can work, so booking her empties the aggregate view too.
        $this->reem->forceFill(['is_bookable' => false])->save();

        $this->assertContains('12:00', $this->times());

        $this->bookAt('12:00', $this->sara);

        $this->assertNotContains(
            '12:00',
            $this->times(),
            'The staff-agnostic view still advertises a slot nobody can serve.',
        );
    }

    /**
     * A rolled-back booking must leave the cache generation untouched.
     *
     * This is what ShouldHandleEventsAfterCommit buys: invalidating from inside
     * BookingService would fire even on the losing side of a slot race, evicting
     * an entry that was still perfectly accurate and forcing a needless
     * recomputation on the next request.
     */
    public function test_a_rolled_back_booking_does_not_bump_the_generation(): void
    {
        $cache = app(\App\Domain\Scheduling\AvailabilityCache::class);

        $this->bookAt('18:00');

        $generationAfterSuccess = $cache->generation($this->store->id, $this->sara->id);

        // This attempt fails inside the transaction and rolls back.
        try {
            $this->bookAt('18:00');
            $this->fail('The duplicate booking should have been refused.');
        } catch (\App\Domain\Booking\Exceptions\SlotNoLongerAvailable) {
            // expected
        }

        $this->assertSame(
            $generationAfterSuccess,
            $cache->generation($this->store->id, $this->sara->id),
            'A failed booking evicted cache entries that were still correct.',
        );
    }

    // =====================================================================
    // The cache must remain a cache — not the source of truth (STEP 6)
    // =====================================================================

    public function test_a_stale_cache_never_lets_a_second_booking_through(): void
    {
        $this->times($this->sara);

        $this->bookAt('17:00');

        // Deliberately re-prime the cache with a stale entry, exactly as a race
        // between two readers could. The booking API must STILL refuse.
        Cache::flush();
        $this->times($this->sara);

        $this->expectException(\App\Domain\Booking\Exceptions\SlotNoLongerAvailable::class);
        $this->bookAt('17:00');
    }
}
