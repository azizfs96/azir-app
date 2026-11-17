import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Banknote, Bike, Clock, MapPin, Phone, ShoppingBasket } from 'lucide-react'
import { api, errorMessage } from '@/api/client'
import type { Driver, Order } from '@/api/types'
import { useT } from '@/app/i18n'
import { Button } from '@/components/ui/Button'
import { PageHeader } from '@/components/shared/PageHeader'
import { TrackingMap } from '@/features/orders/TrackingMap'
import { cn } from '@/lib/cn'
import { GROCERY_COLUMNS, GroceryStatusBadge, groceryColumnOf, nextGroceryAction, type GroceryColumn } from './groceryOrders'

/**
 * The supermarket's delivery board — a four-column flow instead of the
 * restaurant's single list: جديد → جاري التحضير → جاري التوصيل → تم الإيصال.
 * Every order is paid on delivery, so each card tells the driver what to collect.
 */
export function GroceryOrdersPage() {
  const t = useT()
  const o = t.grocery.orders
  const queryClient = useQueryClient()
  const [filter, setFilter] = useState<'active' | 'past'>('active')
  const [error, setError] = useState<string | null>(null)

  const { data: orders, isLoading } = useQuery({
    queryKey: ['merchant-orders', filter],
    queryFn: async () => (await api.get<{ data: Order[] }>(`/merchant/orders?filter=${filter}`)).data.data,
    refetchInterval: filter === 'active' ? 8000 : false,
  })

  // Delivered orders leave the active feed; the board's last column shows
  // the ones handed over today so the day's work stays visible.
  const { data: pastOrders } = useQuery({
    queryKey: ['merchant-orders', 'past'],
    queryFn: async () => (await api.get<{ data: Order[] }>('/merchant/orders?filter=past')).data.data,
    enabled: filter === 'active',
    refetchInterval: 30_000,
  })

  const { data: drivers } = useQuery({
    queryKey: ['drivers'],
    queryFn: async () => (await api.get<{ data: Driver[] }>('/merchant/drivers')).data.data,
    staleTime: 60_000,
  })

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ['merchant-orders'] })
    void queryClient.invalidateQueries({ queryKey: ['grocery-dashboard'] })
  }

  const update = useMutation({
    mutationFn: async (vars: { id: number; status: string }) =>
      (await api.post(`/merchant/orders/${vars.id}/status`, vars)).data,
    onSuccess: () => { setError(null); invalidate() },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const assign = useMutation({
    mutationFn: async (vars: { id: number; driver_id: number }) =>
      (await api.post(`/merchant/orders/${vars.id}/driver`, { driver_id: vars.driver_id })).data,
    onSuccess: () => { setError(null); invalidate() },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const list = orders ?? []
  const today = new Date().toDateString()
  const deliveredToday = (pastOrders ?? []).filter(
    (o) => o.status === 'completed' && o.completed_at && new Date(o.completed_at).toDateString() === today,
  )
  const busy = update.isPending || assign.isPending
  const activeDrivers = (drivers ?? []).filter((d) => d.is_active)

  const card = (order: Order) => (
    <OrderCard
      key={order.id}
      order={order}
      busy={busy}
      drivers={activeDrivers}
      onUpdate={(status) => update.mutate({ id: order.id, status })}
      onAssign={(driver_id) => assign.mutate({ id: order.id, driver_id })}
    />
  )

  return (
    <>
      <PageHeader
        title={o.title}
        subtitle={o.subtitle}
        action={
          <div className="flex rounded-lg bg-ink-100 p-1">
            {(['active', 'past'] as const).map((f) => (
              <button
                key={f}
                onClick={() => setFilter(f)}
                className={cn(
                  'rounded-md px-4 py-1.5 text-sm font-medium transition-colors',
                  filter === f ? 'bg-white text-ink-900 shadow-sm' : 'text-ink-500',
                )}
              >
                {o[f]}
              </button>
            ))}
          </div>
        }
      />

      {error && (
        <div className="mb-4 rounded-lg border border-bad-600/25 bg-bad-50 px-4 py-2.5 text-sm text-bad-600">{error}</div>
      )}

      {isLoading ? (
        <p className="text-sm text-ink-400">{t.common.loading}</p>
      ) : filter === 'past' ? (
        list.length === 0 ? (
          <Empty label={o.empty} />
        ) : (
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">{list.map(card)}</div>
        )
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          {GROCERY_COLUMNS.map((column) => {
            const inColumn = column === 'completed'
              ? deliveredToday
              : list.filter((order) => groceryColumnOf(order.status) === column)
            return (
              <section key={column} className="min-w-0">
                <header className="mb-3 flex items-center justify-between px-1">
                  <h2 className="text-sm font-semibold text-ink-900">
                    {column === 'completed' ? o.deliveredToday : o.columns[column]}
                  </h2>
                  <span className={cn('rounded-full px-2 py-0.5 text-xs font-semibold', columnTone(column))}>
                    {inColumn.length}
                  </span>
                </header>
                <div className="space-y-3">
                  {inColumn.length === 0 ? (
                    <div className="rounded-2xl border border-dashed border-ink-200 py-8 text-center text-xs text-ink-400">
                      {o.empty}
                    </div>
                  ) : inColumn.map(card)}
                </div>
              </section>
            )
          })}
        </div>
      )}
    </>
  )
}

function columnTone(column: GroceryColumn) {
  return {
    placed: 'bg-warn-50 text-warn-600',
    preparing: 'bg-info-50 text-info-600',
    out_for_delivery: 'bg-fresh-100 text-fresh-800',
    completed: 'bg-ink-100 text-ink-700',
  }[column]
}

function Empty({ label }: { label: string }) {
  return (
    <div className="rounded-xl border border-dashed border-ink-200 py-16 text-center">
      <ShoppingBasket className="mx-auto mb-3 size-8 text-ink-300" />
      <p className="text-sm text-ink-500">{label}</p>
    </div>
  )
}

function OrderCard({
  order, busy, drivers, onUpdate, onAssign,
}: {
  order: Order
  busy: boolean
  drivers: Driver[]
  onUpdate: (status: string) => void
  onAssign: (driverId: number) => void
}) {
  const t = useT()
  const o = t.grocery.orders
  const [showMap, setShowMap] = useState(false)
  const column = groceryColumnOf(order.status)
  const next = nextGroceryAction(order.status, t)
  const moving = order.status === 'out_for_delivery'
  const terminal = ['completed', 'rejected', 'cancelled'].includes(order.status)
  const time = order.created_at
    ? new Date(order.created_at).toLocaleTimeString('ar', { hour: '2-digit', minute: '2-digit' })
    : ''

  return (
    <article className="rounded-2xl border border-ink-200 bg-white p-4">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <span className="font-semibold text-ink-900">#{order.reference}</span>
            <GroceryStatusBadge status={order.status} />
          </div>
          <div className="mt-1 flex items-center gap-1 text-xs text-ink-400">
            <Clock className="size-3" /> {time}
            {order.customer?.name && <span>· {order.customer.name}</span>}
          </div>
        </div>
        <div className="text-end">
          <div className="font-bold tabular-nums text-ink-900">{order.total} {t.common.currency}</div>
          <div className="mt-0.5 inline-flex items-center gap-1 rounded-md bg-fresh-50 px-1.5 py-0.5 text-[11px] font-medium text-fresh-800">
            <Banknote className="size-3" /> {o.cod}
          </div>
        </div>
      </div>

      {order.customer?.phone && (
        <a href={`tel:${order.customer.phone}`} className="mt-2 inline-flex items-center gap-1.5 text-xs text-ink-500 hover:text-ink-900">
          <Phone className="size-3" /> <span dir="ltr">{order.customer.phone}</span>
        </a>
      )}

      {order.delivery?.address && (
        <p className="mt-2 flex items-start gap-1 text-xs text-ink-500">
          <MapPin className="mt-0.5 size-3 shrink-0" />
          <span>
            {order.delivery.address}
            {order.delivery.details ? ` — ${order.delivery.details}` : ''}
            {order.delivery.distance_km != null && (
              <span className="text-ink-400"> · {t.orders.distanceKm(order.delivery.distance_km)}</span>
            )}
          </span>
        </p>
      )}

      <ul className="mt-3 space-y-1 border-t border-ink-100 pt-3 text-sm">
        {order.items.map((item) => (
          <li key={item.id} className="flex justify-between gap-2">
            <span className="min-w-0 truncate text-ink-800">
              <span className="inline-block w-6 font-semibold tabular-nums text-ink-900">{item.quantity}×</span>{item.name}
            </span>
            <span className="shrink-0 tabular-nums text-ink-500">{item.line_total}</span>
          </li>
        ))}
      </ul>

      {order.customer_notes && (
        <p className="mt-2 rounded-lg bg-ink-50 px-3 py-2 text-xs text-ink-600">{o.notes}: {order.customer_notes}</p>
      )}

      {!terminal && column !== 'placed' && (
        <div className="mt-3 flex flex-wrap items-center gap-2 rounded-lg border border-ink-100 px-3 py-2 text-xs">
          <Bike className="size-3.5 text-ink-400" />
          {order.driver
            ? <span className="font-semibold text-ink-900">{order.driver.name}</span>
            : <span className="text-ink-400">{t.orders.unassigned}</span>}
          {drivers.length > 0 ? (
            <select
              disabled={busy}
              value={order.driver?.id ?? ''}
              onChange={(e) => e.target.value && onAssign(Number(e.target.value))}
              className="ms-auto h-8 max-w-[10rem] rounded-md border border-ink-200 bg-white px-2 text-xs"
              aria-label={order.driver ? t.orders.changeDriver : t.orders.assignDriver}
            >
              <option value="">{order.driver ? t.orders.changeDriver : t.orders.assignDriver}</option>
              {drivers.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </select>
          ) : (
            !order.driver && <span className="ms-auto text-ink-400">{t.orders.noDrivers}</span>
          )}
          {order.driver && !moving && (
            <button onClick={() => setShowMap((v) => !v)} className="text-ink-500 underline-offset-2 hover:underline">
              {showMap ? t.orders.hideMap : t.orders.showMap}
            </button>
          )}
        </div>
      )}
      {(showMap || moving) && order.driver && <TrackingMap orderId={order.id} active={moving} />}

      {column === 'placed' && (
        <div className="mt-4 flex gap-2">
          <Button className="flex-1 bg-fresh-700 hover:bg-fresh-800" disabled={busy} onClick={() => onUpdate('preparing')}>
            {o.startPreparing}
          </Button>
          <Button variant="danger" disabled={busy} onClick={() => confirm(o.reject + '?') && onUpdate('rejected')}>
            {o.reject}
          </Button>
        </div>
      )}
      {column !== 'placed' && next && (
        <Button className={cn('mt-4 w-full', moving ? 'bg-ink-900' : 'bg-fresh-700 hover:bg-fresh-800')} disabled={busy}
          onClick={() => onUpdate(next.status)}>
          {moving && <span className="me-1 text-xs font-normal opacity-80">{o.collect(order.total.toFixed(2))} ·</span>}
          {next.label}
        </Button>
      )}
    </article>
  )
}
