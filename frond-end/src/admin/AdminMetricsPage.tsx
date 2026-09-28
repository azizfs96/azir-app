import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'
import { useT } from '@/app/i18n'
import { PageHeader } from '@/components/shared/PageHeader'

interface Metrics {
  merchants: { total: number; pending: number; approved: number; suspended: number; rejected: number }
  stores: { total: number; published: number }
  customers: { total: number; new_this_month: number }
  bookings: { total: number; this_month: number; completed: number; cancelled: number }
  qr: { total_scans: number; scans_this_month: number }
}

/**
 * Platform metrics (spec §39).
 *
 * Deliberately small — §40 rules out advanced analytics for the MVP. These are
 * the numbers that say whether the QR → merchant → booking hypothesis works.
 */
export function AdminMetricsPage() {
  const t = useT()

  const { data, isLoading } = useQuery({
    queryKey: ['admin-metrics'],
    queryFn: async () => (await api.get<Metrics>('/admin/metrics')).data,
  })

  if (isLoading || !data) return <p className="text-sm text-ink-500">{t.common.loading}</p>

  const tiles = [
    { label: t.admin.totalMerchants, value: data.merchants.total, tone: 'text-ink-900' },
    { label: t.admin.pendingQueue, value: data.merchants.pending, tone: 'text-warn-600' },
    { label: t.admin.publishedStores, value: data.stores.published, tone: 'text-ink-900' },
    { label: t.admin.totalCustomers, value: data.customers.total, tone: 'text-ink-900' },
    { label: t.admin.totalBookings, value: data.bookings.total, tone: 'text-ink-900' },
    { label: t.admin.totalScans, value: data.qr.total_scans, tone: 'text-accent-600' },
  ]

  return (
    <>
      <PageHeader title={t.admin.metrics} />
      <div className="grid grid-cols-2 gap-px overflow-hidden rounded-[10px] border border-ink-200 bg-ink-200 sm:grid-cols-3">
        {tiles.map((tile) => (
          <div key={tile.label} className="bg-white px-5 py-5">
            <div className={`text-2xl font-semibold tabular-nums ${tile.tone}`}>{tile.value}</div>
            <div className="mt-0.5 text-xs text-ink-500">{tile.label}</div>
          </div>
        ))}
      </div>
    </>
  )
}
