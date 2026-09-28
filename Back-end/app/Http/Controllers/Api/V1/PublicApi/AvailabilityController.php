<?php

namespace App\Http\Controllers\Api\V1\PublicApi;

use App\Domain\Discovery\StoreResolver;
use App\Domain\Scheduling\AvailabilityCache;
use App\Domain\Scheduling\AvailabilityEngine;
use App\Domain\Scheduling\Slot;
use App\Http\Controllers\Controller;
use App\Models\Branch;
use App\Models\Service;
use App\Models\Staff;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Validator;

/**
 * GET /stores/{token}/availability (spec §17, §36).
 *
 * Public: a customer picks a time before signing in, and is only asked to
 * authenticate at confirmation (spec §41).
 */
class AvailabilityController extends Controller
{
    public function __construct(
        private readonly StoreResolver $resolver,
        private readonly AvailabilityEngine $availability,
        private readonly AvailabilityCache $cache,
    ) {}

    public function index(string $token, Request $request): JsonResponse
    {
        $store = $this->resolver->resolve($token);

        if ($store === null) {
            return response()->json([
                'message' => __('errors.invalid_store_code'),
                'error_code' => 'STORE_NOT_FOUND',
            ], 404);
        }

        $data = Validator::make($request->all(), [
            'service_id' => ['required', 'integer'],
            'date' => ['required', 'date_format:Y-m-d'],
            'branch_id' => ['sometimes', 'nullable', 'integer'],
            'staff_id' => ['sometimes', 'nullable', 'integer'],
            // Optional multi-day fetch, so a calendar can grey out full days in
            // one round trip instead of one request per date.
            'days' => ['sometimes', 'integer', 'min:1', 'max:14'],
        ])->validate();

        /*
         * Resolve every id THROUGH the store.
         *
         * A service or staff id from the client is untrusted input; scoping the
         * lookup to this store means a token for salon A can never enumerate or
         * book against salon B's catalogue.
         */
        $service = Service::where('store_id', $store->id)
            ->where('is_active', true)
            ->find($data['service_id']);

        if ($service === null) {
            return response()->json([
                'message' => __('errors.not_found'),
                'error_code' => 'SERVICE_NOT_FOUND',
            ], 404);
        }

        $branch = isset($data['branch_id'])
            ? Branch::where('store_id', $store->id)->where('is_active', true)->find($data['branch_id'])
            : $store->defaultBranch();

        $staff = isset($data['staff_id'])
            ? Staff::where('store_id', $store->id)->with(['schedules', 'services'])->find($data['staff_id'])
            : null;

        // A staff id the customer should never have seen: refuse rather than
        // silently ignoring it and booking them with someone else.
        if (isset($data['staff_id']) && $staff === null) {
            return response()->json([
                'message' => __('errors.not_found'),
                'error_code' => 'STAFF_NOT_FOUND',
            ], 404);
        }

        $days = (int) ($data['days'] ?? 1);
        $startDate = CarbonImmutable::parse($data['date'], $store->timezone);

        /*
         * Read the cache generation ONCE for the whole request.
         *
         * `days` can ask for a fortnight, and looking the generation up per day
         * meant fourteen extra round trips to the cache store for a value that
         * is identical across them.
         */
        $generation = $this->cache->generation($store->id, $staff?->id);

        $result = [];

        for ($offset = 0; $offset < $days; $offset++) {
            $date = $startDate->addDays($offset);

            $result[] = [
                'date' => $date->format('Y-m-d'),
                'slots' => $this->cachedSlots($store, $service, $date, $branch, $staff, $generation),
            ];
        }

        return response()->json([
            'timezone' => $store->timezone,
            'service_id' => $service->id,
            'duration_minutes' => $service->duration_minutes,
            'branch_id' => $branch?->id,
            'days' => $result,
        ]);
    }

    /**
     * Short-lived cache (§6.5).
     *
     * 60 seconds is deliberately brief: long enough to absorb a customer
     * tapping between dates, short enough that a slot taken by someone else
     * disappears quickly. It is only ever a display optimisation — the
     * authoritative check happens under a lock at booking time (§6.3).
     *
     * WHAT GOES INTO THE CACHE: the serialised response arrays, never Slot
     * objects. The `database` store unserialises with an allowed-classes list,
     * so a cached object comes back as __PHP_Incomplete_Class and the endpoint
     * 500s on every warm hit — while the array driver the tests run on stores
     * objects untouched and hides the whole failure. Primitives behave the
     * same on every driver. The timezone is baked in, which is safe because it
     * is a per-store constant and the store id is part of the key.
     *
     * @return array<int, array<string, mixed>>
     */
    private function cachedSlots(
        $store, Service $service, CarbonImmutable $date, ?Branch $branch, ?Staff $staff, int $generation,
    ): array {
        // The key carries a generation number, so a booking (or a schedule
        // change) makes every stale entry unreachable in a single write —
        // see AvailabilityCache.
        $key = $this->cache->key(
            $generation,
            $store->id,
            $service->id,
            $date->format('Y-m-d'),
            $branch?->id,
            $staff?->id,
        );

        $ttl = (int) config('wasla.booking.availability_cache_seconds', 60);

        return Cache::remember($key, $ttl, fn () => array_map(
            fn (Slot $slot) => $slot->toArray($store->timezone),
            $this->availability->slotsFor($store, $service, $date, $branch, $staff)->all(),
        ));
    }
}
