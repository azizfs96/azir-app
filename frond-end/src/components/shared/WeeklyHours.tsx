import { Copy, Plus, X } from 'lucide-react'
import { useI18n } from '@/app/i18n'
import { Button } from '@/components/ui/Button'
import { cn } from '@/lib/cn'

/**
 * ============================================================================
 * THE WEEKLY SCHEDULE EDITOR — staff rosters and branch opening hours.
 *
 * The engine has always supported more than this editor exposed: multiple
 * rows per weekday (split shifts around prayer times, §12) and a break per
 * staff shift. The old editor showed ONE from/to pair per day, so it loaded
 * only the first shift and saved without breaks — and because both endpoints
 * replace the week wholesale, every save from the dashboard silently DELETED
 * the second shift and any break the row had.
 *
 * Model: a day is closed, or it has 1..MAX_SHIFTS shifts; a shift optionally
 * carries a break (staff only — branch rows have no break columns).
 * ============================================================================
 */

export interface Shift {
  from: string
  to: string
  breakFrom?: string
  breakTo?: string
}

export interface DayHours {
  day_of_week: number
  closed: boolean
  shifts: Shift[]
}

/** The 21-row API cap is 3 rows per day; the editor enforces it up front. */
export const MAX_SHIFTS_PER_DAY = 3

const DAY_LABELS_AR = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت']
const DAY_LABELS_EN = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

const freshShift = (): Shift => ({ from: '10:00', to: '22:00' })

/** The Saudi week starts Sunday, matching day_of_week 0..6 on the server. */
export function defaultWeek(): DayHours[] {
  return Array.from({ length: 7 }, (_, day) => ({
    day_of_week: day,
    closed: false,
    shifts: [freshShift()],
  }))
}

/**
 * Rebuild editor state from API rows — ALL rows per day, breaks included.
 *
 * `is_off`/`is_closed` rows and absent days both mean closed; the engine
 * treats them identically, and the editor shows one honest state for both.
 */
export function weekFromSchedule(
  rows: Array<{
    day_of_week: number
    starts_at?: string | null
    ends_at?: string | null
    opens_at?: string | null
    closes_at?: string | null
    break_starts_at?: string | null
    break_ends_at?: string | null
    is_off?: boolean
    is_closed?: boolean
  }>,
): DayHours[] {
  return defaultWeek().map((day) => {
    const matches = rows.filter(
      (row) => row.day_of_week === day.day_of_week && !row.is_off && !row.is_closed,
    )

    if (matches.length === 0) {
      return { ...day, closed: true }
    }

    return {
      ...day,
      closed: false,
      shifts: matches.slice(0, MAX_SHIFTS_PER_DAY).map((row) => ({
        from: (row.starts_at ?? row.opens_at ?? '10:00').slice(0, 5),
        to: (row.ends_at ?? row.closes_at ?? '22:00').slice(0, 5),
        breakFrom: row.break_starts_at?.slice(0, 5) ?? undefined,
        breakTo: row.break_ends_at?.slice(0, 5) ?? undefined,
      })),
    }
  })
}

/** Serialize for PUT …/schedule. Closed days are simply absent — same meaning. */
export function scheduleFromWeek(
  week: DayHours[],
  keys: { from: string; to: string; withBreaks: boolean },
): Array<Record<string, unknown>> {
  return week
    .filter((day) => !day.closed)
    .flatMap((day) =>
      day.shifts.map((shift) => ({
        day_of_week: day.day_of_week,
        [keys.from]: shift.from,
        [keys.to]: shift.to,
        ...(keys.withBreaks
          ? {
              break_starts_at: shift.breakFrom || null,
              break_ends_at: shift.breakTo || null,
            }
          : {}),
      })),
    )
}

const toMinutes = (time: string): number => {
  const [h, m] = time.split(':').map(Number)
  return h * 60 + m
}

/** A shift whose end is at or before its start runs past midnight (engine rule). */
export const crossesMidnight = (shift: Shift): boolean =>
  toMinutes(shift.to) <= toMinutes(shift.from)

/**
 * Business validation the inputs cannot express. Returns localized messages;
 * an empty array means the week is saveable.
 *
 * Cross-midnight shifts are allowed — the engine supports night shifts — but
 * they are flagged visibly in the row instead of being silently reinterpreted.
 */
export function validateWeek(
  week: DayHours[],
  labels: readonly string[],
  messages: { breakOutside: string; breakInverted: string; overlap: string },
): string[] {
  const errors: string[] = []

  for (const day of week) {
    if (day.closed) continue

    for (const shift of day.shifts) {
      const hasBreakStart = Boolean(shift.breakFrom)
      const hasBreakEnd = Boolean(shift.breakTo)

      if (hasBreakStart !== hasBreakEnd) {
        errors.push(`${labels[day.day_of_week]}: ${messages.breakInverted}`)
        continue
      }

      if (hasBreakStart && hasBreakEnd) {
        if (toMinutes(shift.breakFrom!) >= toMinutes(shift.breakTo!)) {
          errors.push(`${labels[day.day_of_week]}: ${messages.breakInverted}`)
        } else if (
          // Containment is only checkable for same-day shifts; a night shift's
          // break is left to the merchant's judgement.
          !crossesMidnight(shift) &&
          (toMinutes(shift.breakFrom!) < toMinutes(shift.from) ||
            toMinutes(shift.breakTo!) > toMinutes(shift.to))
        ) {
          errors.push(`${labels[day.day_of_week]}: ${messages.breakOutside}`)
        }
      }
    }

    // Two shifts in one day must not overlap each other (both same-day).
    const sameDay = day.shifts.filter((shift) => !crossesMidnight(shift))
    const sorted = [...sameDay].sort((a, b) => toMinutes(a.from) - toMinutes(b.from))

    for (let i = 1; i < sorted.length; i++) {
      if (toMinutes(sorted[i].from) < toMinutes(sorted[i - 1].to)) {
        errors.push(`${labels[day.day_of_week]}: ${messages.overlap}`)
        break
      }
    }
  }

  return [...new Set(errors)]
}

/**
 * Every quarter hour of the day. If the stored value sits off the grid
 * (legacy rows like 10:11), it is kept as an extra option so the merchant
 * sees the truth and can move off it — never a silently "corrected" value.
 */
function timeOptions(current: string): string[] {
  const options = new Set<string>()

  for (let minutes = 0; minutes < 24 * 60; minutes += 15) {
    const h = String(Math.floor(minutes / 60)).padStart(2, '0')
    const m = String(minutes % 60).padStart(2, '0')
    options.add(`${h}:${m}`)
  }

  if (current) options.add(current)

  return [...options].sort()
}

function format12h(value: string, locale: string): string {
  const [h, m] = value.split(':').map(Number)
  const suffix = h < 12 ? (locale === 'en' ? 'AM' : 'ص') : (locale === 'en' ? 'PM' : 'م')
  const hour = h % 12 === 0 ? 12 : h % 12

  return `${hour}:${String(m).padStart(2, '0')} ${suffix}`
}

/**
 * A select, not <input type="time">: the native control's sub-fields
 * (hour/minute/AM-PM) are fiddly and misbehave in RTL layouts — merchants
 * reported not being able to edit the time at all. One tap on a select opens
 * a scrollable list of quarter-hours in familiar 12-hour wording; typing "9"
 * jumps straight there.
 */
export function TimeSelect({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const { locale } = useI18n()

  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="h-9 cursor-pointer rounded-lg border border-ink-200 bg-white px-2 text-sm tabular-nums"
    >
      {timeOptions(value).map((time) => (
        <option key={time} value={time}>{format12h(time, locale)}</option>
      ))}
    </select>
  )
}

export function WeeklyHours({
  week, onChange, onSave, saving, withBreaks = false, errors = [],
}: {
  week: DayHours[]
  onChange: (week: DayHours[]) => void
  onSave: () => void
  saving?: boolean
  /** Staff shifts carry breaks; branch opening hours do not. */
  withBreaks?: boolean
  errors?: string[]
}) {
  const { t, locale } = useI18n()
  const labels = locale === 'en' ? DAY_LABELS_EN : DAY_LABELS_AR
  const hours = t.weeklyHours

  const updateDay = (index: number, patch: Partial<DayHours>) =>
    onChange(week.map((day, i) => (i === index ? { ...day, ...patch } : day)))

  /** Set every day to this day's hours — the "we open the same time daily" shortcut. */
  const copyToAllDays = (dayIndex: number) =>
    onChange(week.map((day) => ({
      ...day,
      closed: week[dayIndex].closed,
      shifts: week[dayIndex].shifts.map((shift) => ({ ...shift })),
    })))

  const updateShift = (dayIndex: number, shiftIndex: number, patch: Partial<Shift>) =>
    updateDay(dayIndex, {
      shifts: week[dayIndex].shifts.map((shift, i) =>
        i === shiftIndex ? { ...shift, ...patch } : shift,
      ),
    })

  return (
    <div>
      <ul className="divide-y divide-ink-200">
        {week.map((day, dayIndex) => (
          <li key={day.day_of_week} className="px-5 py-3">
            <div className="flex items-center gap-3">
              <span className="w-20 shrink-0 text-sm text-ink-900">{labels[day.day_of_week]}</span>

              <button
                onClick={() =>
                  updateDay(dayIndex, {
                    closed: !day.closed,
                    shifts: day.shifts.length === 0 ? [freshShift()] : day.shifts,
                  })
                }
                className={cn(
                  'rounded-md px-2 py-1 text-xs font-medium transition-colors',
                  day.closed ? 'bg-ink-100 text-ink-500' : 'bg-ok-50 text-ok-600',
                )}
              >
                {day.closed ? t.branchesPage.closed : '✓'}
              </button>

              <div className="ms-auto flex items-center gap-1">
                {!day.closed && day.shifts.length < MAX_SHIFTS_PER_DAY && (
                  <button
                    onClick={() => updateDay(dayIndex, { shifts: [...day.shifts, freshShift()] })}
                    className="flex items-center gap-1 rounded-md px-2 py-1 text-xs font-medium text-brand-600 hover:bg-brand-50"
                  >
                    <Plus className="size-3.5" />
                    {hours.addShift}
                  </button>
                )}
                <button
                  onClick={() => copyToAllDays(dayIndex)}
                  title={hours.copyToAll}
                  aria-label={hours.copyToAll}
                  className="flex items-center gap-1 rounded-md px-2 py-1 text-xs text-ink-400 hover:bg-ink-100 hover:text-ink-600"
                >
                  <Copy className="size-3.5" />
                  {hours.copyToAll}
                </button>
              </div>
            </div>

            {!day.closed && (
              <div className="mt-2 space-y-2">
                {day.shifts.map((shift, shiftIndex) => (
                  <div
                    key={shiftIndex}
                    className="flex flex-wrap items-center gap-x-3 gap-y-2 rounded-lg bg-ink-50 px-3 py-2"
                  >
                    <div className="flex items-center gap-2">
                      <TimeSelect
                        value={shift.from}
                        onChange={(from) => updateShift(dayIndex, shiftIndex, { from })}
                      />
                      <span className="text-ink-400">—</span>
                      <TimeSelect
                        value={shift.to}
                        onChange={(to) => updateShift(dayIndex, shiftIndex, { to })}
                      />

                      {crossesMidnight(shift) && (
                        // Not an error — the engine treats end<=start as a
                        // night shift into the next day. Saying so makes an
                        // accidental inversion visible before it is saved.
                        <span className="rounded-md bg-warn-50 px-1.5 py-0.5 text-[11px] font-medium text-warn-600">
                          {hours.nextDay}
                        </span>
                      )}
                    </div>

                    {withBreaks && (
                      shift.breakFrom !== undefined || shift.breakTo !== undefined ? (
                        <div className="flex items-center gap-2">
                          <span className="text-xs text-ink-500">{hours.breakLabel}</span>
                          <TimeSelect
                            value={shift.breakFrom ?? '13:00'}
                            onChange={(breakFrom) => updateShift(dayIndex, shiftIndex, { breakFrom })}
                          />
                          <span className="text-ink-400">—</span>
                          <TimeSelect
                            value={shift.breakTo ?? '14:00'}
                            onChange={(breakTo) => updateShift(dayIndex, shiftIndex, { breakTo })}
                          />
                          <button
                            onClick={() =>
                              updateShift(dayIndex, shiftIndex, { breakFrom: undefined, breakTo: undefined })
                            }
                            aria-label={hours.removeBreak}
                            className="rounded-md p-1 text-ink-400 hover:bg-ink-100"
                          >
                            <X className="size-3.5" />
                          </button>
                        </div>
                      ) : (
                        <button
                          onClick={() =>
                            updateShift(dayIndex, shiftIndex, { breakFrom: '13:00', breakTo: '14:00' })
                          }
                          className="rounded-md px-2 py-1 text-xs text-ink-500 hover:bg-ink-100"
                        >
                          + {hours.addBreak}
                        </button>
                      )
                    )}

                    {day.shifts.length > 1 && (
                      <button
                        onClick={() =>
                          updateDay(dayIndex, {
                            shifts: day.shifts.filter((_, i) => i !== shiftIndex),
                          })
                        }
                        aria-label={hours.removeShift}
                        className="ms-auto rounded-md p-1 text-ink-400 hover:bg-bad-50 hover:text-bad-600"
                      >
                        <X className="size-4" />
                      </button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </li>
        ))}
      </ul>

      {errors.length > 0 && (
        <div className="mx-5 mb-3 rounded-lg border border-bad-600/25 bg-bad-50 px-4 py-2.5 text-sm text-bad-600">
          {errors.map((message) => <div key={message}>{message}</div>)}
        </div>
      )}

      <div className="flex justify-end border-t border-ink-200 px-5 py-3">
        <Button size="sm" loading={saving} onClick={onSave}>{t.common.save}</Button>
      </div>
    </div>
  )
}
