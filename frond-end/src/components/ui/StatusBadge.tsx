import { cn } from '@/lib/cn'
import { useT } from '@/app/i18n'
import type { BookingStatus } from '@/api/types'

/*
 * Booking status (spec §19).
 * Tinted background + solid text, no borders — legible at a glance in a dense
 * table without turning the row into a christmas tree.
 */
const styles: Record<BookingStatus, string> = {
  pending: 'bg-warn-50 text-warn-600',
  confirmed: 'bg-info-50 text-info-600',
  checked_in: 'bg-accent-50 text-accent-600',
  completed: 'bg-ok-50 text-ok-600',
  cancelled: 'bg-ink-100 text-ink-500',
  no_show: 'bg-bad-50 text-bad-600',
}

export function StatusBadge({ status }: { status: BookingStatus }) {
  const t = useT()

  return (
    <span className={cn(
      'inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium whitespace-nowrap',
      styles[status],
    )}>
      {t.status[status]}
    </span>
  )
}
