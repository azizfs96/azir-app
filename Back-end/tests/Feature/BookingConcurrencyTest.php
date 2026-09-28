<?php

namespace Tests\Feature;

use App\Domain\Booking\BookingStatus;
use App\Models\Booking;
use App\Models\BookingSettings;
use App\Models\Branch;
use App\Models\Customer;
use App\Models\Merchant;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use App\Models\User;
use App\Support\TenantContext;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Testing\DatabaseTruncation;
use Tests\TestCase;

/**
 * ============================================================================
 * THE DOUBLE-BOOKING GUARD, PROVED WITH REAL CONCURRENCY
 *
 * Every other booking test in this suite runs sequentially in one process, so
 * the second attempt always sees the first booking already committed. Those
 * tests prove the RE-CHECK works. They prove nothing about the LOCK.
 *
 * This class spawns genuine OS processes — separate PHP runtimes, separate
 * database connections, separate transactions — and releases them at the same
 * microsecond via a wall-clock barrier (tests/Concurrency/attempt_booking.php).
 *
 * NOTE ON DatabaseTruncation: RefreshDatabase wraps each test in a transaction
 * that is rolled back, so the seeded rows would be invisible to a second
 * process and its writes invisible to us. Truncation commits, which is what
 * cross-process testing requires.
 * ============================================================================
 */
class BookingConcurrencyTest extends TestCase
{
    use DatabaseTruncation;

    private const TZ = 'Asia/Riyadh';

    private Store $store;

    private Branch $branch;

    private Staff $sara;

    private Staff $reem;

    private Service $haircut;

    private Customer $customer;

    protected function setUp(): void
    {
        parent::setUp();

        $merchant = Merchant::factory()->create();
        app(TenantContext::class)->setTenant($merchant);

        $this->store = Store::factory()->create(['merchant_id' => $merchant->id]);

        BookingSettings::create(array_merge(BookingSettings::defaults(), [
            'store_id' => $this->store->id,
            'min_lead_time_minutes' => 0,
            'max_advance_days' => 365,
            // Keep the transaction focused on the lock under test.
            'auto_confirm' => false,
        ]));

        $this->branch = Branch::factory()->forStore($this->store)->create([
            'slot_interval_minutes' => 30,
            'buffer_before_minutes' => 0,
            'buffer_after_minutes' => 0,
        ]);

        foreach (range(0, 6) as $day) {
            $this->branch->schedules()->create([
                'day_of_week' => $day, 'opens_at' => '08:00', 'closes_at' => '23:00',
            ]);
        }

        $this->sara = $this->makeStaff('Sara');
        $this->reem = $this->makeStaff('Reem');

        $this->haircut = Service::factory()->forStore($this->store)->create([
            'name_en' => 'Hair Cut',
            'duration_minutes' => 60,
            'buffer_after_minutes' => 0,
            'price' => 100,
        ]);

        $user = User::factory()->customer()->create();
        $this->customer = Customer::create(['user_id' => $user->id, 'first_name' => 'Race']);

        app(TenantContext::class)->setTenant(null);
    }

    /**
     * Leave the database as we found it.
     *
     * DatabaseTruncation COMMITS its data (it must — other processes have to
     * see it). RefreshDatabase tests that run afterwards only wrap themselves
     * in a transaction, so anything left behind here leaks into them and shows
     * up as phantom rows. Truncating on the way out keeps this class from
     * polluting the rest of the suite.
     */
    protected function tearDown(): void
    {
        $this->truncateTablesForAllConnections();

        parent::tearDown();
    }

    private function makeStaff(string $name): Staff
    {
        $staff = Staff::factory()->forStore($this->store)->create([
            'name' => $name,
            'branch_id' => $this->branch->id,
        ]);

        foreach (range(0, 6) as $day) {
            $staff->schedules()->create([
                'day_of_week' => $day, 'starts_at' => '08:00', 'ends_at' => '23:00',
            ]);
        }

        return $staff;
    }

    private function at(string $ymd, int $hour, int $minute = 0): CarbonImmutable
    {
        return CarbonImmutable::parse($ymd, self::TZ)->setTime($hour, $minute);
    }

    /**
     * Launch N booking attempts in parallel, all released at the same instant.
     *
     * @param  array<int, array{staff: ?Staff, startsAt: CarbonImmutable}>  $attempts
     * @return array<int, array<string, mixed>>
     */
    private function race(array $attempts): array
    {
        $script = base_path('tests/Concurrency/attempt_booking.php');
        $database = config('database.connections.mysql.database');

        // Enough lead time for every child to boot Laravel and reach the spin
        // loop before the barrier opens.
        $releaseAt = microtime(true) + 2.5;

        $processes = [];

        foreach ($attempts as $i => $attempt) {
            $command = implode(' ', array_map('escapeshellarg', [
                PHP_BINARY,
                $script,
                $database,
                (string) $this->store->id,
                (string) $this->haircut->id,
                (string) $this->branch->id,
                $attempt['staff'] === null ? 'null' : (string) $attempt['staff']->id,
                $attempt['startsAt']->toIso8601String(),
                (string) $releaseAt,
                (string) $this->customer->id,
            ]));

            $processes[$i] = proc_open(
                $command,
                [1 => ['pipe', 'w'], 2 => ['pipe', 'w']],
                $pipes[$i],
                null,
                ['WASLA_TEST_ISOLATION' => getenv('WASLA_TEST_ISOLATION') ?: ''] + getenv(),
            );
        }

        $results = [];

        foreach ($processes as $i => $process) {
            $stdout = stream_get_contents($pipes[$i][1]);
            $stderr = stream_get_contents($pipes[$i][2]);

            fclose($pipes[$i][1]);
            fclose($pipes[$i][2]);
            proc_close($process);

            $decoded = json_decode(trim($stdout), true);

            $results[$i] = is_array($decoded)
                ? $decoded
                : ['ok' => false, 'code' => 'NO_OUTPUT', 'stdout' => $stdout, 'stderr' => $stderr];
        }

        return $results;
    }

    /** Bookings that actually occupy the calendar for a staff member. */
    private function blockingCountFor(?int $staffId): int
    {
        return Booking::query()
            ->withoutGlobalScopes()
            ->where('staff_id', $staffId)
            ->whereIn('booking_status', BookingStatus::blockingValues())
            ->count();
    }

    private function summarise(array $results): string
    {
        return collect($results)
            ->map(fn ($r, $i) => "  [$i] ".json_encode($r, JSON_UNESCAPED_UNICODE))
            ->implode("\n");
    }

    // =====================================================================
    // TEST 1 — same staff, same slot, both explicit
    // =====================================================================

    public function test_two_concurrent_requests_for_the_same_staff_and_slot(): void
    {
        $when = $this->at('2026-11-02', 19);

        $results = $this->race([
            ['staff' => $this->sara, 'startsAt' => $when],
            ['staff' => $this->sara, 'startsAt' => $when],
        ]);

        $succeeded = collect($results)->where('ok', true)->count();

        $this->assertSame(
            1,
            $succeeded,
            "Exactly one booking must win the race.\n".$this->summarise($results),
        );

        $this->assertSame(
            1,
            $this->blockingCountFor($this->sara->id),
            "The database must hold exactly one blocking booking for Sara.\n".$this->summarise($results),
        );

        $this->assertSame(
            ['SLOT_TAKEN'],
            collect($results)->where('ok', false)->pluck('code')->all(),
            "The loser must fail with the existing conflict behaviour.\n".$this->summarise($results),
        );
    }

    // =====================================================================
    // TEST 2 — "any staff": two requests must not land on the same person
    // =====================================================================

    public function test_two_concurrent_any_staff_requests_do_not_share_a_staff_member(): void
    {
        $when = $this->at('2026-11-03', 19);

        // Two stylists exist, so BOTH requests may legitimately succeed — but
        // they must be assigned to different people.
        $results = $this->race([
            ['staff' => null, 'startsAt' => $when],
            ['staff' => null, 'startsAt' => $when],
        ]);

        $assigned = collect($results)->where('ok', true)->pluck('staff_id')->filter()->all();

        $this->assertSame(
            count($assigned),
            count(array_unique($assigned)),
            "Auto-assignment gave the same stylist to two bookings.\n".$this->summarise($results),
        );

        foreach ([$this->sara->id, $this->reem->id] as $staffId) {
            $this->assertLessThanOrEqual(
                1,
                $this->blockingCountFor($staffId),
                "More than one booking landed on staff {$staffId}.\n".$this->summarise($results),
            );
        }
    }

    // =====================================================================
    // TEST 2b — the sharpest case: auto-assign racing an explicit pick
    // =====================================================================

    public function test_explicit_and_auto_assignment_cannot_both_take_the_same_staff(): void
    {
        // Only ONE stylist can serve this slot, so both paths must converge on
        // Sara — the exact collision the two lock targets used to miss.
        $this->reem->forceFill(['is_bookable' => false])->save();

        $when = $this->at('2026-11-04', 19);

        $results = $this->race([
            ['staff' => $this->sara, 'startsAt' => $when],  // locks the staff row
            ['staff' => null, 'startsAt' => $when],         // locks the branch row
        ]);

        $this->assertSame(
            1,
            $this->blockingCountFor($this->sara->id),
            "Explicit and automatic paths both booked Sara.\n".$this->summarise($results),
        );

        $this->assertSame(
            1,
            collect($results)->where('ok', true)->count(),
            "Exactly one of the two paths must succeed.\n".$this->summarise($results),
        );

        /*
         * THE ASSERTION THAT PROVES THE FIX.
         *
         * Before the lock targets were unified this test still passed — but the
         * loser failed with a raw InnoDB deadlock (SQLSTATE 40001) surfaced as
         * an HTTP 500 with SQL in the body, because the two paths locked
         * different rows and then each waited on the other's row via foreign
         * key checks. Now the loser must lose cleanly.
         */
        $this->assertSame(
            ['SLOT_TAKEN'],
            collect($results)->where('ok', false)->pluck('code')->all(),
            "The loser must fail with SLOT_TAKEN, not a database deadlock.\n".$this->summarise($results),
        );
    }

    // =====================================================================
    // TEST 4 — different staff at the same time must both succeed
    // =====================================================================

    public function test_two_different_staff_at_the_same_time_both_succeed(): void
    {
        $when = $this->at('2026-11-05', 19);

        $results = $this->race([
            ['staff' => $this->sara, 'startsAt' => $when],
            ['staff' => $this->reem, 'startsAt' => $when],
        ]);

        $this->assertSame(
            2,
            collect($results)->where('ok', true)->count(),
            "Independent stylists must not block each other.\n".$this->summarise($results),
        );
    }

    // =====================================================================
    // TEST 5 — adjacent bookings are legal (intervals are half-open)
    // =====================================================================

    public function test_adjacent_bookings_both_succeed(): void
    {
        $results = $this->race([
            ['staff' => $this->sara, 'startsAt' => $this->at('2026-11-06', 19)],
            ['staff' => $this->sara, 'startsAt' => $this->at('2026-11-06', 20)],
        ]);

        $this->assertSame(
            2,
            collect($results)->where('ok', true)->count(),
            "19:00-20:00 and 20:00-21:00 do not overlap.\n".$this->summarise($results),
        );
    }

    // =====================================================================
    // TEST 6 — partial overlap must be rejected
    // =====================================================================

    public function test_overlapping_bookings_reject_the_second(): void
    {
        // 19:00-20:00 against 19:30-20:30 — a 30-minute overlap, which no
        // exact-match constraint could catch.
        $results = $this->race([
            ['staff' => $this->sara, 'startsAt' => $this->at('2026-11-07', 19)],
            ['staff' => $this->sara, 'startsAt' => $this->at('2026-11-07', 19, 30)],
        ]);

        $this->assertSame(
            1,
            $this->blockingCountFor($this->sara->id),
            "Overlapping bookings were both accepted.\n".$this->summarise($results),
        );
    }

    // =====================================================================
    // Heavier contention — five racers, one slot
    // =====================================================================

    public function test_five_concurrent_requests_yield_exactly_one_booking(): void
    {
        $when = $this->at('2026-11-08', 19);

        $results = $this->race(array_fill(0, 5, [
            'staff' => $this->sara,
            'startsAt' => $when,
        ]));

        $this->assertSame(
            1,
            $this->blockingCountFor($this->sara->id),
            "Five racers produced more than one booking.\n".$this->summarise($results),
        );

        // Nobody may fail with a raw database error — losers get the domain
        // exception, which the API renders as 409 SLOT_TAKEN.
        $unexpected = collect($results)->where('code', 'ERROR')->all();

        $this->assertSame(
            [],
            $unexpected,
            "A racer failed with an unhandled error instead of SLOT_TAKEN.\n".$this->summarise($results),
        );
    }
}
