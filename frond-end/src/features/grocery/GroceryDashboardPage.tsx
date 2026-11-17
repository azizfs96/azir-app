import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { AlertTriangle, Bike, Clock, PackageCheck, ShoppingBasket, TrendingUp } from 'lucide-react'
import { api, errorMessage, mediaUrl } from '@/api/client'
import type { GroceryDashboardData, Order } from '@/api/types'
import { useT } from '@/app/i18n'
import { Card, CardHeader } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { EmptyState } from '@/components/shared/EmptyState'
import { PageHeader } from '@/components/shared/PageHeader'
import { cn } from '@/lib/cn'
import { useState } from 'react'
import { GroceryStatusBadge, nextGroceryAction } from './groceryOrders'

/**
 * The supermarket home: today's delivery board, revenue, stock that is running
 * low, the month's best sellers, and the orders waiting on the merchant —
 * each with its one next action right there.
 */
export function GroceryDashboardPage() {
  const t = useT()
  const queryClient = useQueryClient()
  const [error, setError] = useState<string | null>(null)

  const { data, isLoading, isError } = useQuery({
    queryKey: ['grocery-dashboard'],
    queryFn: async () => (await api.get<GroceryDashboardData>('/merchant/grocery/dashboard')).data,
    refetchInterval: 15_000,
  })

  const update = useMutation({
    mutationFn: async (vars: { id: number; status: string }) =>
      (await api.post(`/merchant/orders/${vars.id}/status`, vars)).data,
    onSuccess: () => {
      setError(null)
      void queryClient.invalidateQueries({ queryKey: ['grocery-dashboard'] })
      void queryClient.invalidateQueries({ queryKey: ['merchant-orders'] })
    },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  if (isLoading) return <p className="text-sm text-ink-500">{t.common.loading}</p>
  if (isError || !data) return <p className="text-sm text-bad-600">{t.common.error}</p>

  const g = t.grocery.dashboard
  const tiles = [
    { label: g.new, value: data.today.new, icon: ShoppingBasket, tone: 'text-warn-600 bg-warn-50' },
    { label: g.preparing, value: data.today.preparing, icon: Clock, tone: 'text-info-600 bg-info-50' },
    { label: g.outForDelivery, value: data.today.out_for_delivery, icon: Bike, tone: 'text-fresh-700 bg-fresh-100' },
    { label: g.delivered, value: data.today.delivered, icon: PackageCheck, tone: 'text-ink-900 bg-ink-100' },
  ]
  const max = Math.max(1, ...data.revenue.series.map((d) => d.revenue))

  return (
    <>
      <PageHeader title={g.title} subtitle={`${data.store.name} · ${data.date}`} />

      {!data.store.is_published && (
        <div className="mb-6 flex items-center justify-between gap-4 rounded-[10px] border border-warn-600/25 bg-warn-50 px-4 py-3">
          <p className="text-sm text-warn-600">{t.dashboard.notPublished}</p>
          <Link to="/settings"><Button size="sm" variant="secondary">{t.dashboard.publishNow}</Button></Link>
        </div>
      )}

      {error && (
        <div className="mb-4 rounded-lg border border-bad-600/25 bg-bad-50 px-4 py-2.5 text-sm text-bad-600">{error}</div>
      )}

      {/* Today's board — one tile per stage of a grocery order. */}
      <div className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        {tiles.map(({ label, value, icon: Icon, tone }) => (
          <div key={label} className="flex items-center gap-3 rounded-2xl border border-ink-200 bg-white px-4 py-4">
            <span className={cn('flex size-10 shrink-0 items-center justify-center rounded-xl', tone)}>
              <Icon className="size-5" />
            </span>
            <div>
              <div className="text-2xl font-semibold tabular-nums text-ink-900">{value}</div>
              <div className="text-xs text-ink-500">{label}</div>
            </div>
          </div>
        ))}
      </div>

      <div className="grid gap-5 lg:grid-cols-3">
        {/* Revenue */}
        <Card className="lg:col-span-1">
          <div className="px-5 py-5">
            <div className="flex items-center gap-2 text-xs text-ink-500">
              <TrendingUp className="size-3.5" /> {g.revenueToday}
            </div>
            <div className="mt-1 text-3xl font-semibold tabular-nums text-ink-900">
              {data.revenue.today.toLocaleString()}{' '}
              <span className="text-base font-normal text-ink-500">{t.common.currency}</span>
            </div>
            <div className="mt-1 text-xs text-ink-400">{g.revenueBasis}</div>

            <div className="mt-5 flex items-end gap-1.5" aria-hidden>
              {data.revenue.series.map((d) => (
                <div key={d.date} className="flex flex-1 flex-col items-center gap-1">
                  <div
                    className="w-full rounded-t-md bg-fresh-500/80"
                    style={{ height: `${Math.max(4, (d.revenue / max) * 56)}px` }}
                    title={`${d.date}: ${d.revenue}`}
                  />
                  <span className="text-[10px] text-ink-400">{d.date.slice(-2)}</span>
                </div>
              ))}
            </div>
            <div className="mt-3 flex justify-between text-xs text-ink-500">
              <span>{g.revenueWeek}</span>
              <span className="font-semibold tabular-nums text-ink-900">{data.revenue.week.toLocaleString()} {t.common.currency}</span>
            </div>
            <div className="mt-3 flex justify-between text-xs text-ink-500">
              <span>{g.ordersToday}</span>
              <span className="font-semibold tabular-nums text-ink-900">{data.today.orders}</span>
            </div>
          </div>
        </Card>

        {/* Needs action */}
        <Card className="lg:col-span-2">
          <CardHeader
            title={g.needsAction}
            action={<Link to="/grocery-orders" className="text-xs font-medium text-fresh-700 hover:underline">{g.viewAll}</Link>}
          />
          {data.needs_action.length === 0 ? (
            <EmptyState title={g.nothingPending} />
          ) : (
            <ul className="divide-y divide-ink-200">
              {data.needs_action.map((order) => (
                <ActionRow key={order.id} order={order} busy={update.isPending} onUpdate={(status) => update.mutate({ id: order.id, status })} />
              ))}
            </ul>
          )}
        </Card>

        {/* Low stock */}
        <Card className="lg:col-span-2">
          <CardHeader
            title={
              <span className="flex items-center gap-2">
                {g.lowStock}
                {data.catalog.out_of_stock > 0 && (
                  <span className="rounded-md bg-bad-50 px-2 py-0.5 text-xs font-normal text-bad-600">
                    {data.catalog.out_of_stock} {g.outOfStock}
                  </span>
                )}
              </span>
            }
            action={<Link to="/catalog" className="text-xs font-medium text-fresh-700 hover:underline">{g.manageStock}</Link>}
          />
          {data.catalog.low_stock.length === 0 ? (
            <EmptyState title={g.noLowStock} />
          ) : (
            <ul className="divide-y divide-ink-200">
              {data.catalog.low_stock.map((p) => (
                <li key={p.id} className="flex items-center gap-3 px-5 py-2.5">
                  <Thumb image={p.image} />
                  <span className="min-w-0 flex-1 truncate text-sm text-ink-900">
                    {p.name}{p.unit && <span className="text-ink-400"> · {p.unit}</span>}
                  </span>
                  <span className={cn(
                    'inline-flex items-center gap-1 rounded-md px-2 py-0.5 text-xs font-semibold',
                    p.stock_quantity === 0 ? 'bg-bad-50 text-bad-600' : 'bg-warn-50 text-warn-600',
                  )}>
                    <AlertTriangle className="size-3" /> {g.left(p.stock_quantity)}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </Card>

        {/* Best sellers */}
        <Card className="lg:col-span-1">
          <CardHeader title={g.bestSellers} />
          {data.best_sellers.length === 0 ? (
            <EmptyState title={g.noSales} />
          ) : (
            <ol className="divide-y divide-ink-200">
              {data.best_sellers.map((row, i) => (
                <li key={row.item_id} className="flex items-center gap-3 px-5 py-2.5">
                  <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-fresh-100 text-xs font-bold text-fresh-800">{i + 1}</span>
                  <span className="min-w-0 flex-1 truncate text-sm text-ink-900">{row.name}</span>
                  <span className="text-xs text-ink-500">{g.sold(row.quantity)}</span>
                </li>
              ))}
            </ol>
          )}
        </Card>
      </div>
    </>
  )
}

function Thumb({ image }: { image: string | null }) {
  return image ? (
    <img src={mediaUrl(image) ?? undefined} alt="" className="size-9 shrink-0 rounded-lg object-cover" />
  ) : (
    <span className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-fresh-50 text-fresh-700">
      <ShoppingBasket className="size-4" />
    </span>
  )
}

function ActionRow({ order, busy, onUpdate }: { order: Order; busy: boolean; onUpdate: (status: string) => void }) {
  const t = useT()
  const next = nextGroceryAction(order.status, t)
  const time = order.created_at
    ? new Date(order.created_at).toLocaleTimeString('ar', { hour: '2-digit', minute: '2-digit' })
    : ''

  return (
    <li className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 py-3">
      <span className="w-12 shrink-0 text-xs tabular-nums text-ink-400">{time}</span>
      <span className="min-w-0 flex-1 truncate text-sm text-ink-900">
        <span className="font-semibold">#{order.reference}</span>
        {order.customer?.name && <span className="text-ink-500"> · {order.customer.name}</span>}
        <span className="text-ink-400"> · {t.grocery.orders.items(order.items.length)}</span>
      </span>
      <span className="text-sm font-semibold tabular-nums text-ink-900">{order.total} {t.common.currency}</span>
      <GroceryStatusBadge status={order.status} />
      {next && (
        <Button size="sm" onClick={() => onUpdate(next.status)} disabled={busy}
          className="bg-fresh-700 hover:bg-fresh-800">
          {next.label}
        </Button>
      )}
    </li>
  )
}
