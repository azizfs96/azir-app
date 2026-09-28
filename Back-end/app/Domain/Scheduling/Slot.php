<?php

namespace App\Domain\Scheduling;

use Carbon\CarbonImmutable;

/**
 * One bookable start time (spec §17).
 *
 * `staffId` is null when the merchant does not expose staff selection — the
 * customer picks a TIME, and StaffAssigner decides who serves them at booking
 * time (spec §9 Merchant B).
 */
final class Slot
{
    public function __construct(
        public readonly CarbonImmutable $startsAt,
        public readonly CarbonImmutable $endsAt,
        public readonly ?int $staffId = null,
        public readonly ?string $staffName = null,
    ) {}

    /**
     * Strip staff identity for merchants that hide it. The slot is still real;
     * the customer just is not shown who will serve them.
     */
    public function withoutStaff(): self
    {
        return new self($this->startsAt, $this->endsAt, null, null);
    }

    public function durationMinutes(): int
    {
        return (int) $this->startsAt->diffInMinutes($this->endsAt);
    }

    /**
     * Rendered in the STORE's timezone with an explicit offset, so the client
     * never has to guess (ARCHITECTURE.md §5.4).
     *
     * @return array<string, mixed>
     */
    public function toArray(string $timezone = 'Asia/Riyadh'): array
    {
        return [
            'starts_at' => $this->startsAt->setTimezone($timezone)->toIso8601String(),
            'ends_at' => $this->endsAt->setTimezone($timezone)->toIso8601String(),
            'time' => $this->startsAt->setTimezone($timezone)->format('H:i'),
            'staff_id' => $this->staffId,
            'staff_name' => $this->staffName,
        ];
    }
}
