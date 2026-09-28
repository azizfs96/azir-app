<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * ============================================================================
 * A DATABASE-LEVEL BACKSTOP AGAINST DOUBLE BOOKING
 *
 * The primary guard is the row lock in BookingService (staff row on every
 * path). This constraint exists so that if that discipline is ever broken —
 * a new code path, a refactor, a direct SQL import — the database still
 * refuses the most common collision instead of silently accepting it.
 *
 * WHAT IT COVERS
 *   Two ACTIVE bookings for the same resource starting at the SAME instant.
 *   That is the overwhelmingly common race: two customers tapping the same
 *   slot chip at the same moment.
 *
 * WHAT IT DOES NOT COVER — AND WHY
 *   Partial overlaps (10:00-11:00 against 10:30-11:30) are NOT caught. MySQL
 *   8.4 has no exclusion constraints (PostgreSQL's `EXCLUDE USING gist` with
 *   tstzrange would express this directly) and a UNIQUE index cannot describe
 *   a range intersection. A CHECK constraint cannot query other rows either.
 *
 *   So overlap protection remains the row lock's job. This constraint narrows
 *   the blast radius; it does not replace the lock.
 *
 * NULL SEMANTICS DO THE FILTERING
 *   The generated column is NULL unless the booking is active, and MySQL
 *   ignores NULLs in unique indexes. A cancelled, no-show, completed or
 *   soft-deleted booking therefore releases its slot automatically — matching
 *   BookingStatus::blocksAvailability() and the SoftDeletes global scope
 *   exactly. Change one and you must change the other.
 * ============================================================================
 */
return new class extends Migration
{
    public function up(): void
    {
        // Guard against a partially applied migration on re-run.
        if (Schema::hasColumn('bookings', 'active_slot_key')) {
            return;
        }

        /*
         * VIRTUAL, not STORED.
         *
         * A STORED generated column forces a full table rebuild, which MySQL
         * refuses here because `bookings` carries a self-referencing foreign
         * key (rescheduled_from_booking_id). VIRTUAL is added in place, and
         * MySQL 8 indexes virtual columns perfectly well — the index itself is
         * materialised, which is all the constraint needs.
         */
        DB::statement("
            ALTER TABLE `bookings`
            ADD COLUMN `active_slot_key` VARCHAR(96)
                GENERATED ALWAYS AS (
                    CASE
                        WHEN `deleted_at` IS NULL
                         AND `booking_status` IN ('pending', 'confirmed', 'checked_in')
                        THEN CONCAT_WS(
                            '|',
                            -- Staff bookings key on the stylist; staff-less
                            -- stores key on the branch, which is the resource.
                            COALESCE(CONCAT('s', `staff_id`), CONCAT('b', `branch_id`)),
                            `starts_at`
                        )
                    END
                ) VIRTUAL
        ");

        DB::statement('
            CREATE UNIQUE INDEX `bookings_active_slot_unq`
            ON `bookings` (`active_slot_key`)
        ');
    }

    public function down(): void
    {
        if (! Schema::hasColumn('bookings', 'active_slot_key')) {
            return;
        }

        DB::statement('DROP INDEX `bookings_active_slot_unq` ON `bookings`');
        DB::statement('ALTER TABLE `bookings` DROP COLUMN `active_slot_key`');
    }
};
