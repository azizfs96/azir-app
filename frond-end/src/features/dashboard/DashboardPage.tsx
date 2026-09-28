import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { api } from '@/api/client'
import type { DashboardData } from '@/api/types'
import { useT } from '@/app/i18n'
import { Card, CardHeader } from '@/components/ui/Card'
import { StatusBadge } from '@/components/ui/StatusBadge'
import { EmptyState } from '@/components/shared/EmptyState'
import { PageHeader } from '@/components/shared/PageHeader'
import { Button } from '@/components/ui/Button'

/**
 * Merchant dashboard (spec §13).
 *
 *   Today · 24 Bookings · 18 Confirmed · 4 Completed · 1 Cancelled · 1 No-show
 *   Revenue SAR 4,850
 *   Upcoming 10:00 Sara · 11:30 Reem · 13:00 Ahmed
 */
export function DashboardPage() {
  const t = useT()

  const { data, isLoading, isError } = useQuery({
    queryKey: ['dashboard'],
    queryFn: async () => (await api.get<DashboardData>('/merchant/dashboard')).data,
    // The merchant leaves this open on a tablet at reception all day.
    refetchInterval: 60_000,
  })

  if (isLoading) return <p className="text-sm text-ink-500">{t.common.loading}</p>
  if (isError || !data) return <p className="text-sm text-bad-600">{t.common.error}</p>

  const stats = [
    { label: t.dashboard.bookings, value: data.today.total, tone: 'text-ink-900' },
    { label: t.dashboard.confirmed, value: data.today.confirmed, tone: 'text-info-600' },
    { label: t.dashboard.completed, value: data.today.completed, tone: 'text-ok-600' },
    { label: t.dashboard.cancelled, value: data.today.cancelled, tone: 'text-ink-500' },
    { label: t.dashboard.noShow, value: data.today.no_show, tone: 'text-bad-600' },
  ]

  return (
    <>
      <PageHeader title={t.dashboard.title} subtitle={data.date} />

      {/* An unpublished store takes no bookings at all — say so loudly. */}
      {!data.store.is_published && (
        <div className="mb-6 flex items-center justify-between gap-4 rounded-[10px] border border-warn-600/25 bg-warn-50 px-4 py-3">
          <p className="text-sm text-warn-600">{t.dashboard.notPublished}</p>
          <Link to="/settings">
            <Button size="sm" variant="secondary">{t.dashboard.publishNow}</Button>
          </Link>
        </div>
      )}

      {/*
        Numbers first, big and unadorned. No sparklines, no gradient tiles —
        the merchant needs "how many people are coming today", not a data
        visualisation exercise (spec §32).
      */}
      <div className="mb-6 grid grid-cols-2 gap-px overflow-hidden rounded-[10px] border border-ink-200 bg-ink-200 sm:grid-cols-3 lg:grid-cols-5">
        {stats.map((stat) => (
          <div key={stat.label} className="bg-white px-4 py-4">
            <div className={`text-2xl font-semibold tabular-nums ${stat.tone}`}>{stat.value}</div>
            <div className="mt-0.5 text-xs text-ink-500">{stat.label}</div>
          </div>
        ))}
      </div>

      <div className="grid gap-5 lg:grid-cols-3">
        <Card className="lg:col-span-1">
          <div className="px-5 py-5">
            <div className="text-xs text-ink-500">{t.dashboard.revenue}</div>
            <div className="mt-1 text-2xl font-semibold tabular-nums text-ink-900">
              {data.revenue.amount.toLocaleString()}{' '}
              <span className="text-base font-normal text-ink-500">{t.common.currency}</span>
            </div>
            {/* Being explicit about the basis prevents "why did revenue drop?" */}
            <div className="mt-1 text-xs text-ink-400">{t.dashboard.revenueBasis}</div>
          </div>
        </Card>

        <Card className="lg:col-span-2">
          <CardHeader title={t.dashboard.upcoming} />
          {data.upcoming.length === 0 ? (
            <EmptyState title={t.dashboard.noUpcoming} />
          ) : (
            <ul className="divide-y divide-ink-200">
              {data.upcoming.map((booking) => (
                <li key={booking.id} className="flex items-center gap-4 px-5 py-3">
                  <span className="w-12 shrink-0 text-sm font-medium tabular-nums text-ink-900">
                    {booking.time}
                  </span>
                  <span className="min-w-0 flex-1 truncate text-sm text-ink-900">
                    {booking.customer ?? '—'}
                    {booking.service && (
                      <span className="text-ink-400"> · {booking.service}</span>
                    )}
                  </span>
                  {booking.staff && (
                    <span className="hidden shrink-0 text-xs text-ink-400 sm:block">
                      {booking.staff}
                    </span>
                  )}
                  <StatusBadge status={booking.status} />
                </li>
              ))}
            </ul>
          )}
        </Card>
      </div>
    </>
  )
}
