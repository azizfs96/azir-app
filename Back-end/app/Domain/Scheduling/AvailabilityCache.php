<?php

namespace App\Domain\Scheduling;

use Illuminate\Support\Facades\Cache;

/**
 * ============================================================================
 * AVAILABILITY CACHE KEYS AND INVALIDATION (audit finding C-2)
 *
 * The slot list is cached for 60 seconds. Nothing cleared it, so for up to a
 * minute after a booking the API kept advertising the slot that had just been
 * taken and every customer who tapped it got 409 SLOT_TAKEN.
 *
 * WHY A GENERATION COUNTER RATHER THAN DELETING KEYS
 *
 * One booking invalidates many keys: the slot list is cached per SERVICE, and a
 * 60-minute booking blocks time for every service the store offers, at both the
 * explicit-branch and default-branch variants. Enumerating and deleting that
 * cross-product would be several writes and would silently miss any key shape
 * added later.
 *
 * Instead each cached key embeds a generation number. Bumping the generation
 * makes every old key unreachable in ONE write; the orphans expire on their own
 * 60 seconds later. It also works on the `database` cache driver this project
 * uses, which supports no tagging at all (only redis/memcached do).
 *
 * SCOPE — deliberately two-dimensional:
 *
 *   availability-gen:{storeId}:{staffId}   bumped when THAT stylist changes
 *   availability-gen:{storeId}:any         bumped when anything changes
 *
 * Booking Sara bumps Sara's generation and the aggregate one. Reem's cached
 * entries keep their generation and survive — and no other merchant is touched,
 * because the store id is part of every generation key.
 *
 * THE CACHE IS NEVER THE SOURCE OF TRUTH. It only decides what the storefront
 * DISPLAYS. Whether a booking may be written is settled by the row lock and the
 * re-check inside BookingService's transaction, which this class never touches.
 * ============================================================================
 */
class AvailabilityCache
{
    /** Aggregate scope: requests that did not name a staff member. */
    public const ANY = 'any';

    /**
     * Generations outlive the 60-second slot entries on purpose — a generation
     * that expired would silently resurrect stale keys.
     */
    private const GENERATION_TTL_DAYS = 30;

    /**
     * The cache key for one slot list, carrying its generation.
     */
    public function key(
        int $generation,
        int $storeId,
        int $serviceId,
        string $date,
        ?int $branchId,
        ?int $staffId,
    ): string {
        return sprintf(
            'availability:g%d:%d:%d:%s:%s:%s',
            $generation,
            $storeId,
            $serviceId,
            $date,
            $branchId ?? self::ANY,
            $staffId ?? self::ANY,
        );
    }

    /**
     * The current generation for a store, optionally narrowed to one stylist.
     *
     * Deliberately NOT memoised on this object: the container does not
     * guarantee one instance per request, and an instance that outlives a
     * request would hand back a generation from a previous one — serving the
     * exact stale slot list this class exists to prevent. Callers that need it
     * more than once (the multi-day loop) read it once and pass it down.
     */
    public function generation(int $storeId, ?int $staffId): int
    {
        return (int) Cache::get($this->generationKey($storeId, $staffId), 0);
    }

    /**
     * Invalidate everything cached for one stylist at one store.
     *
     * Bumps the aggregate scope too: a staff-agnostic slot list is the union of
     * every stylist's free time, so it goes stale the moment any one of them
     * does. Two writes, and no other stylist or merchant is affected.
     */
    public function forgetStaff(int $storeId, ?int $staffId): void
    {
        if ($staffId !== null) {
            $this->bump($storeId, $staffId);
        }

        $this->bump($storeId, null);
    }

    /**
     * Invalidate every scope for a store.
     *
     * For changes that affect all stylists at once — branch opening hours, or a
     * service duration, which alters how slots are generated for everyone.
     * Still strictly tenant-scoped: only this store's generations move.
     *
     * @param  array<int, int>  $staffIds  stylists whose scoped keys must also move
     */
    public function forgetStore(int $storeId, array $staffIds = []): void
    {
        foreach (array_unique($staffIds) as $staffId) {
            $this->bump($storeId, $staffId);
        }

        $this->bump($storeId, null);
    }

    /**
     * Advance one generation.
     *
     * Read-then-write rather than Cache::increment(): the database and array
     * stores do not increment a key that does not exist yet. A lost update
     * between two concurrent bumps is harmless — the number still changed,
     * which is the only property invalidation depends on.
     */
    private function bump(int $storeId, ?int $staffId): void
    {
        $key = $this->generationKey($storeId, $staffId);

        Cache::put(
            $key,
            $this->generation($storeId, $staffId) + 1,
            now()->addDays(self::GENERATION_TTL_DAYS),
        );
    }

    private function generationKey(int $storeId, ?int $staffId): string
    {
        return sprintf('availability-gen:%d:%s', $storeId, $staffId ?? self::ANY);
    }
}
