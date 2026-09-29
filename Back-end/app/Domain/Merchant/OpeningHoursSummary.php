<?php

namespace App\Domain\Merchant;

use App\Models\Branch;

/**
 * Turns a week of branch_schedules into one readable line.
 *
 *   الأحد - الخميس · 10:00 ص - 10:00 م
 *   Sun - Thu · 10:00 AM - 10:00 PM
 *
 * Computed server-side so every client renders identical text, and so the
 * grouping logic (which days share hours) lives in one place rather than being
 * reimplemented in Flutter and React.
 */
class OpeningHoursSummary
{
    /** 0 = Sunday, matching branch_schedules.day_of_week. */
    private const DAYS_AR = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

    private const DAYS_EN = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    /**
     * @return array{days: string, hours: string, is_open_now: bool}|null
     */
    public static function for(Branch $branch, string $locale = 'ar'): ?array
    {
        $rows = $branch->schedules->where('is_closed', false);

        if ($rows->isEmpty()) {
            return null;
        }

        // Group by the open/close pair; the biggest group is the "normal" week,
        // which is what the header should show.
        $byHours = $rows->groupBy(
            fn ($row) => substr((string) $row->opens_at, 0, 5).'-'.substr((string) $row->closes_at, 0, 5)
        );

        $dominant = $byHours->sortByDesc(fn ($group) => $group->count())->first();
        $days = $dominant->pluck('day_of_week')->unique()->sort()->values()->all();

        [$opens, $closes] = explode('-', $byHours->search($dominant));

        $labels = $locale === 'en' ? self::DAYS_EN : self::DAYS_AR;

        return [
            'days' => self::describeDays($days, $labels),
            'hours' => self::formatTime($opens, $locale).' - '.self::formatTime($closes, $locale),
            'is_open_now' => self::isBranchOpenNow($branch),
        ];
    }

    /**
     * "Sun - Thu" for a run, "Sun, Tue, Thu" when the days are scattered.
     *
     * @param  array<int, int>  $days
     * @param  array<int, string>  $labels
     */
    private static function describeDays(array $days, array $labels): string
    {
        if ($days === []) {
            return '';
        }

        if (count($days) === 7) {
            return $labels[0].' - '.$labels[6];
        }

        $isConsecutive = true;

        for ($i = 1; $i < count($days); $i++) {
            if ($days[$i] !== $days[$i - 1] + 1) {
                $isConsecutive = false;
                break;
            }
        }

        if ($isConsecutive && count($days) > 1) {
            return $labels[$days[0]].' - '.$labels[$days[count($days) - 1]];
        }

        return implode('، ', array_map(fn (int $d) => $labels[$d], $days));
    }

    private static function formatTime(string $time, string $locale): string
    {
        [$hour, $minute] = array_pad(explode(':', $time), 2, '00');
        $hour = (int) $hour;

        $period = $locale === 'en'
            ? ($hour < 12 ? 'AM' : 'PM')
            : ($hour < 12 ? 'ص' : 'م');

        $display = $hour % 12 === 0 ? 12 : $hour % 12;

        return "{$display}:{$minute} {$period}";
    }

    /**
     * Whether the branch is open at this moment, in ITS timezone.
     */
    public static function isBranchOpenNow(Branch $branch): bool
    {
        $timezone = $branch->store?->timezone ?? config('wasla.default_timezone');
        $now = now($timezone);

        foreach ($branch->schedules->where('is_closed', false) as $row) {
            if ((int) $row->day_of_week !== (int) $now->dayOfWeek) {
                continue;
            }

            $opens = $now->copy()->setTimeFromTimeString((string) $row->opens_at);
            $closes = $now->copy()->setTimeFromTimeString((string) $row->closes_at);

            // A shift ending past midnight closes on the following day.
            if ($closes->lessThanOrEqualTo($opens)) {
                $closes = $closes->addDay();
            }

            if ($now->betweenIncluded($opens, $closes)) {
                return true;
            }
        }

        return false;
    }
}
