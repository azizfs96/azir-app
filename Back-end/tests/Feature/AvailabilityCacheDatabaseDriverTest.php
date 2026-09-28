<?php

namespace Tests\Feature;

/**
 * ============================================================================
 * THE WHOLE CACHE SUITE AGAIN — ON THE DRIVER PRODUCTION ACTUALLY USES
 *
 * AvailabilityCacheTest runs on the `array` store, which keeps values as live
 * PHP objects. The `database` store SERIALISES them, and on read it
 * unserialises with an allowed-classes list — so a cached Slot object came
 * back as __PHP_Incomplete_Class and the endpoint threw a TypeError on every
 * warm hit. Real phones saw:
 *
 *   open a date  -> 200 (cache miss, computed fresh)
 *   go back to it -> 500 "حدث خطأ" (warm hit, poisoned entry)
 *   retry         -> 500 again, until the 60-second TTL expired
 *
 * Nine passing tests never noticed, because none of them exercised a
 * serialising store. Inheriting the full suite here makes every cache
 * assertion run on both drivers from now on.
 * ============================================================================
 */
class AvailabilityCacheDatabaseDriverTest extends AvailabilityCacheTest
{
    protected function setUp(): void
    {
        parent::setUp();

        // The driver production uses — values now round-trip through
        // serialize()/unserialize() instead of living as PHP objects.
        config(['cache.default' => 'database']);
    }

    /**
     * The exact failure from the device: the SECOND request for the same day
     * is served from the cache, and must be identical to the first — not a
     * 500 because what came back from the store was no longer a Slot.
     */
    public function test_a_warm_cache_hit_returns_the_same_response_not_a_500(): void
    {
        $query = http_build_query([
            'service_id' => $this->haircut->id,
            'date' => $this->date(),
            'staff_id' => $this->sara->id,
        ]);

        $url = "/api/v1/stores/{$this->store->public_token}/availability?{$query}";

        $cold = $this->getJson($url)->assertOk()->json();

        // Same request again, inside the TTL: served from the database cache.
        $warm = $this->getJson($url)->assertOk()->json();

        $this->assertSame($cold, $warm, 'The cached response differs from the computed one.');
        $this->assertNotEmpty($warm['days'][0]['slots'], 'Fixture problem: expected open slots.');
    }
}
