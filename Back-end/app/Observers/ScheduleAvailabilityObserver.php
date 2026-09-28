<?php

namespace App\Observers;

use App\Domain\Scheduling\AvailabilityCache;
use App\Models\BranchSchedule;
use App\Models\Staff;
use App\Models\StaffSchedule;
use App\Models\TimeOff;
use Illuminate\Contracts\Events\ShouldHandleEventsAfterCommit;
use Illuminate\Database\Eloquent\Model;

/**
 * ============================================================================
 * THE OTHER THINGS THAT MAKE CACHED SLOTS WRONG
 *
 * Bookings are the frequent case, but the availability engine also reads
 * working hours and time off. Editing a stylist's Thursday hours, closing a
 * branch for Eid, or granting a day's leave all change which slots exist —
 * and none of them touch the bookings table, so the booking observer would
 * never notice.
 *
 * The merchant dashboard REPLACES a whole week when hours are saved
 * (StaffController::schedule and BranchController::schedule delete every row
 * then re-create it), so these fire several times per save. That is fine: a
 * generation bump is one cache write, and the operation is rare.
 *
 * Like the booking observer, everything here runs only after the transaction
 * commits.
 * ============================================================================
 */
class ScheduleAvailabilityObserver implements ShouldHandleEventsAfterCommit
{
    public function __construct(private readonly AvailabilityCache $cache) {}

    public function created(Model $model): void
    {
        $this->invalidate($model);
    }

    public function updated(Model $model): void
    {
        $this->invalidate($model);
    }

    public function deleted(Model $model): void
    {
        $this->invalidate($model);
    }

    private function invalidate(Model $model): void
    {
        match (true) {
            // One stylist's own hours: only their scope (plus the aggregate).
            $model instanceof StaffSchedule => $this->forStaff($model->staff_id),

            // Branch hours bound every stylist working there, so every scope at
            // that store moves. Still strictly one tenant.
            $model instanceof BranchSchedule => $this->forBranch($model->branch_id),

            // Time off targets exactly one of the two (enforced by the model).
            $model instanceof TimeOff => $model->staff_id !== null
                ? $this->forStaff($model->staff_id)
                : $this->forBranch($model->branch_id),

            default => null,
        };
    }

    private function forStaff(?int $staffId): void
    {
        if ($staffId === null) {
            return;
        }

        $staff = Staff::query()->withoutGlobalScopes()->find($staffId, ['id', 'store_id']);

        if ($staff !== null) {
            $this->cache->forgetStaff((int) $staff->store_id, (int) $staff->id);
        }
    }

    private function forBranch(?int $branchId): void
    {
        if ($branchId === null) {
            return;
        }

        $staff = Staff::query()
            ->withoutGlobalScopes()
            ->where('branch_id', $branchId)
            ->get(['id', 'store_id']);

        if ($staff->isEmpty()) {
            // A branch with no stylists is still bookable as a resource itself
            // (spec §15), so the aggregate scope must still be invalidated.
            $storeId = \App\Models\Branch::query()->withoutGlobalScopes()
                ->where('id', $branchId)->value('store_id');

            if ($storeId !== null) {
                $this->cache->forgetStore((int) $storeId);
            }

            return;
        }

        $this->cache->forgetStore(
            (int) $staff->first()->store_id,
            $staff->pluck('id')->map(fn ($id) => (int) $id)->all(),
        );
    }
}
