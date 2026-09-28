<?php

use Illuminate\Support\Facades\Schedule;

/*
 * Appointment reminders (spec §23).
 *
 * Every 15 minutes rather than hourly: each store configures its own
 * reminder_hours_before, so a coarse schedule would drift a reminder up to an
 * hour away from its intended lead time.
 *
 * withoutOverlapping guards against a slow run being started again on top of
 * itself and double-sending.
 */
Schedule::command('wasla:send-reminders')
    ->everyFifteenMinutes()
    ->withoutOverlapping();
