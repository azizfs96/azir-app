<?php

namespace App\Support;

use Carbon\CarbonImmutable;
use InvalidArgumentException;

/**
 * A half-open time interval [start, end).
 *
 * ============================================================================
 * HALF-OPEN IS THE WHOLE POINT.
 *
 * A booking that ends at 15:00 must NOT conflict with one starting at 15:00.
 * Using a closed interval here would silently lose one slot per boundary all
 * day long, which is the single easiest way to get a scheduling engine subtly
 * wrong. Every comparison below is written to that rule.
 * ============================================================================
 *
 * Immutable — availability maths does a lot of arithmetic on shared values, and
 * mutation bugs there are extremely hard to spot.
 */
final class TimeRange
{
    public function __construct(
        public readonly CarbonImmutable $start,
        public readonly CarbonImmutable $end,
    ) {
        if ($end->lessThanOrEqualTo($start)) {
            throw new InvalidArgumentException(
                "TimeRange end ({$end->toIso8601String()}) must be after start ({$start->toIso8601String()})."
            );
        }
    }

    public static function of(CarbonImmutable $start, CarbonImmutable $end): self
    {
        return new self($start, $end);
    }

    public static function fromDuration(CarbonImmutable $start, int $minutes): self
    {
        return new self($start, $start->addMinutes($minutes));
    }

    public function durationMinutes(): int
    {
        return (int) $this->start->diffInMinutes($this->end);
    }

    /**
     * Do the two intervals share any time at all? Touching endpoints do not.
     */
    public function overlaps(self $other): bool
    {
        return $this->start->lessThan($other->end)
            && $this->end->greaterThan($other->start);
    }

    /**
     * Does this interval fully contain the other?
     */
    public function contains(self $other): bool
    {
        return $this->start->lessThanOrEqualTo($other->start)
            && $this->end->greaterThanOrEqualTo($other->end);
    }

    public function intersect(self $other): ?self
    {
        if (! $this->overlaps($other)) {
            return null;
        }

        return new self(
            $this->start->greaterThan($other->start) ? $this->start : $other->start,
            $this->end->lessThan($other->end) ? $this->end : $other->end,
        );
    }

    /**
     * Remove $other from this interval.
     *
     * Returns 0, 1 or 2 ranges — two when the removed chunk sits in the middle,
     * which is exactly the "staff has a booking in the middle of their shift"
     * case that splits a working day in half.
     *
     * @return array<int, self>
     */
    public function subtract(self $other): array
    {
        if (! $this->overlaps($other)) {
            return [$this];
        }

        $pieces = [];

        // Left remainder.
        if ($this->start->lessThan($other->start)) {
            $pieces[] = new self($this->start, $other->start);
        }

        // Right remainder.
        if ($this->end->greaterThan($other->end)) {
            $pieces[] = new self($other->end, $this->end);
        }

        return $pieces;
    }

    /**
     * Subtract many intervals from many intervals.
     *
     * This is step 3 of the availability algorithm (ARCHITECTURE.md §6.1):
     * take the working windows, then carve out breaks, time off and existing
     * bookings in one pass.
     *
     * @param  array<int, self>  $ranges
     * @param  array<int, self>  $blockers
     * @return array<int, self>
     */
    public static function subtractAll(array $ranges, array $blockers): array
    {
        foreach ($blockers as $blocker) {
            $next = [];

            foreach ($ranges as $range) {
                foreach ($range->subtract($blocker) as $piece) {
                    $next[] = $piece;
                }
            }

            $ranges = $next;

            if ($ranges === []) {
                break;
            }
        }

        return $ranges;
    }

    /**
     * Merge overlapping/adjacent ranges into a minimal set.
     *
     * Adjacent ranges ARE merged (10:00-12:00 and 12:00-14:00 become
     * 10:00-14:00), because a two-hour service should be bookable straight
     * across the seam between two schedule rows.
     *
     * @param  array<int, self>  $ranges
     * @return array<int, self>
     */
    public static function merge(array $ranges): array
    {
        if ($ranges === []) {
            return [];
        }

        usort($ranges, fn (self $a, self $b) => $a->start <=> $b->start);

        $merged = [array_shift($ranges)];

        foreach ($ranges as $range) {
            $last = $merged[count($merged) - 1];

            // <= so that touching ranges join, not just overlapping ones.
            if ($range->start->lessThanOrEqualTo($last->end)) {
                $merged[count($merged) - 1] = new self(
                    $last->start,
                    $range->end->greaterThan($last->end) ? $range->end : $last->end,
                );

                continue;
            }

            $merged[] = $range;
        }

        return $merged;
    }

    public function __toString(): string
    {
        return $this->start->format('H:i').'-'.$this->end->format('H:i');
    }
}
