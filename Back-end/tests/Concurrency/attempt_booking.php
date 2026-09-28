<?php

/**
 * A single booking attempt, run as its OWN OS process.
 *
 * Concurrency cannot be proved from inside one PHPUnit process: PHP is
 * single-threaded, and the test's own transaction would serialise everything.
 * So BookingConcurrencyTest spawns several copies of this script, each with its
 * own PHP process, its own database connection and its own transaction, and
 * releases them all at the same wall-clock instant.
 *
 * Usage (all arguments required):
 *   php attempt_booking.php <db> <storeId> <serviceId> <branchId> <staffId|null> <startsAtIso> <releaseAtUnixFloat>
 *
 * Prints one line of JSON so the parent can classify the outcome.
 */

use App\Domain\Booking\BookingService;
use App\Domain\Booking\Exceptions\SlotNoLongerAvailable;
use App\Models\Branch;
use App\Models\Customer;
use App\Models\Service;
use App\Models\Staff;
use App\Models\Store;
use Carbon\CarbonImmutable;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Support\Facades\DB;

require __DIR__.'/../../vendor/autoload.php';

$app = require __DIR__.'/../../bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

[, $database, $storeId, $serviceId, $branchId, $staffId, $startsAtIso, $releaseAt, $customerId] = $argv;

// The child boots from .env, which points at the development database. Redirect
// it at the test database explicitly rather than relying on env precedence.
config(['database.connections.mysql.database' => $database]);
DB::purge('mysql');

// Optional: run this attempt under a different isolation level, so the test can
// prove whether the current protection survives a READ COMMITTED deployment.
if (($isolation = getenv('WASLA_TEST_ISOLATION')) !== false && $isolation !== '') {
    DB::statement("SET SESSION TRANSACTION ISOLATION LEVEL {$isolation}");
}

try {
    $store = Store::query()->withoutGlobalScopes()->with('bookingSettings')->findOrFail($storeId);
    $service = Service::query()->withoutGlobalScopes()->findOrFail($serviceId);
    $branch = Branch::query()->withoutGlobalScopes()->findOrFail($branchId);

    $staff = $staffId === 'null'
        ? null
        : Staff::query()->withoutGlobalScopes()->with(['schedules', 'services'])->findOrFail($staffId);

    $customer = $customerId === 'null'
        ? null
        : Customer::query()->findOrFail($customerId);

    $startsAt = CarbonImmutable::parse($startsAtIso);

    /*
     * THE BARRIER.
     *
     * Every process spins until the same microsecond, so they enter
     * BookingService::create() together. Without this the processes start
     * milliseconds apart and the first one commits before the second begins —
     * which is exactly the sequential case that hides the bug.
     */
    $target = (float) $releaseAt;
    while (microtime(true) < $target) {
        usleep(100);
    }

    $enteredAt = microtime(true);

    $booking = app(BookingService::class)->create(
        store: $store,
        service: $service,
        startsAt: $startsAt,
        branch: $branch,
        requestedStaff: $staff,
        customer: $customer,
    );

    echo json_encode([
        'ok' => true,
        'booking_id' => $booking->id,
        'staff_id' => $booking->staff_id,
        'reference' => $booking->reference,
        'entered_at' => $enteredAt,
        'finished_at' => microtime(true),
    ]);
} catch (SlotNoLongerAvailable $e) {
    // The expected loser of the race.
    echo json_encode([
        'ok' => false, 'code' => 'SLOT_TAKEN', 'message' => $e->getMessage(),
        'entered_at' => $enteredAt ?? null, 'finished_at' => microtime(true),
    ]);
} catch (Throwable $e) {
    // Anything else is a genuine failure the test should surface, not swallow.
    echo json_encode([
        'ok' => false,
        'code' => 'ERROR',
        'exception' => $e::class,
        'message' => $e->getMessage(),
    ]);
}
