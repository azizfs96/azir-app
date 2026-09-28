import { useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Clock, Phone, Printer, ShoppingBag } from 'lucide-react'
import { QRCodeCanvas } from 'qrcode.react'
import { api } from '@/api/client'
import { useT } from '@/app/i18n'
import { cn } from '@/lib/cn'

/**
 * RESTAURANT ORDERS (RestaurantEngine, R3) — the merchant's live kitchen board.
 *
 * Orders placed in the customer app land here. The merchant accepts (committing
 * a prep time), advances them through preparing → ready → completed, or rejects
 * them. Every move goes through POST /merchant/orders/{id}/status, which the
 * server validates against the order state machine; the customer's tracking
 * screen reflects it. Active orders poll so new ones appear without a refresh.
 */

interface OrderOption { group: string; name: string }
interface OrderItem { id: number; name: string; quantity: number; line_total: number; options?: OrderOption[] }
interface Invoice {
  number: string | null
  seller_name: string | null
  tax_number: string | null
  commercial_registration: string | null
  national_address: string | null
  logo: string | null
  tax_rate: number
  issued_at: string | null
  qr: string | null
}
interface Order {
  id: number
  reference: string
  status: 'placed' | 'accepted' | 'preparing' | 'ready' | 'completed' | 'rejected' | 'cancelled'
  fulfillment_type: 'pickup' | 'dine_in' | 'delivery' | 'curbside'
  table_number: string | null
  subtotal: number
  delivery_fee: number
  tax_amount: number
  total: number
  prep_minutes: number | null
  customer_notes: string | null
  created_at: string | null
  customer?: { name: string | null; phone: string | null }
  items: OrderItem[]
  delivery?: { address: string | null }
  invoice?: Invoice
}

const TERMINAL = ['completed', 'rejected', 'cancelled']

export function OrdersPage() {
  const t = useT()
  const queryClient = useQueryClient()
  const [filter, setFilter] = useState<'active' | 'past'>('active')

  // Orders the merchant just finished stay on the board (as a terminal card with
  // no buttons) instead of vanishing and letting a new order jump into their
  // spot — which read as the order "reverting" to accept/reject.
  const [finished, setFinished] = useState<Order[]>([])

  const { data: orders, isLoading } = useQuery({
    queryKey: ['merchant-orders', filter],
    queryFn: async () =>
      (await api.get<{ data: Order[] }>(`/merchant/orders?filter=${filter}`)).data.data,
    refetchInterval: filter === 'active' ? 8000 : false,
  })

  const update = useMutation({
    mutationFn: async (vars: { id: number; status: string; prep_minutes?: number; reason?: string }) =>
      (await api.post<{ order: Order }>(`/merchant/orders/${vars.id}/status`, vars)).data,
    onSuccess: (data, vars) => {
      if (TERMINAL.includes(vars.status)) {
        setFinished((prev) => [data.order, ...prev.filter((o) => o.id !== data.order.id)])
      }
      void queryClient.invalidateQueries({ queryKey: ['merchant-orders'] })
    },
  })

  // On the active board, keep just-finished orders pinned IN PLACE (sorted by
  // time, newest first) so a completed order simply flips to its terminal badge
  // where it sat — rather than vanishing and letting another order take its
  // spot. Elsewhere show the server list as-is.
  const list: Order[] =
    filter === 'active'
      ? [...(orders ?? []).filter((o) => !finished.some((f) => f.id === o.id)), ...finished].sort(
          (a, b) => (b.created_at ?? '').localeCompare(a.created_at ?? ''),
        )
      : (orders ?? [])

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <h1 className="text-xl font-semibold text-ink-900">{t.orders.title}</h1>
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
              {t.orders[f]}
            </button>
          ))}
        </div>
      </div>

      {isLoading ? (
        <p className="text-sm text-ink-400">{t.common.loading}</p>
      ) : !list.length ? (
        <div className="rounded-xl border border-dashed border-ink-200 py-16 text-center">
          <ShoppingBag className="mx-auto mb-3 size-8 text-ink-300" />
          <p className="text-sm text-ink-500">{t.orders.empty}</p>
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-2">
          {list.map((order) => (
            <OrderCard key={order.id} order={order} onUpdate={update.mutate} busy={update.isPending} />
          ))}
        </div>
      )}
    </div>
  )
}

const STATUS_STYLE: Record<Order['status'], string> = {
  placed: 'bg-amber-100 text-amber-700',
  accepted: 'bg-blue-100 text-blue-700',
  preparing: 'bg-blue-100 text-blue-700',
  ready: 'bg-emerald-100 text-emerald-700',
  completed: 'bg-ink-100 text-ink-600',
  rejected: 'bg-red-100 text-red-700',
  cancelled: 'bg-red-100 text-red-700',
}

function OrderCard({
  order,
  onUpdate,
  busy,
}: {
  order: Order
  onUpdate: (vars: { id: number; status: string; prep_minutes?: number; reason?: string }) => void
  busy: boolean
}) {
  const t = useT()
  const [prep, setPrep] = useState(order.prep_minutes ?? 20)

  const time = order.created_at
    ? new Date(order.created_at).toLocaleTimeString('ar', { hour: '2-digit', minute: '2-digit' })
    : ''

  return (
    <div className="rounded-2xl border border-ink-200 bg-white p-5">
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <span className="font-semibold text-ink-900">#{order.reference}</span>
            <span className={cn('rounded-full px-2.5 py-0.5 text-xs font-semibold', STATUS_STYLE[order.status])}>
              {t.orders.status[order.status]}
            </span>
          </div>
          <div className="mt-1 flex items-center gap-2 text-xs text-ink-400">
            <span>{t.orders.fulfillment[order.fulfillment_type]}</span>
            {order.table_number && <span>· {order.table_number}</span>}
            {time && (
              <span className="flex items-center gap-1">
                · <Clock className="size-3" /> {time}
              </span>
            )}
          </div>
        </div>
        <div className="text-end">
          <div className="font-bold text-ink-900">
            {order.total} {t.common.currency}
          </div>
          {order.customer?.name && <div className="text-xs text-ink-400">{order.customer.name}</div>}
        </div>
      </div>

      {order.customer?.phone && (
        <a
          href={`tel:${order.customer.phone}`}
          className="mt-2 inline-flex items-center gap-1.5 text-xs text-ink-500 hover:text-ink-900"
        >
          <Phone className="size-3" /> {order.customer.phone}
        </a>
      )}

      <div className="mt-3 space-y-1.5 border-t border-ink-100 pt-3">
        {order.items.map((item) => (
          <div key={item.id} className="flex justify-between text-sm">
            <span className="text-ink-800">
              {item.quantity} × {item.name}
              {item.options?.length ? (
                <span className="text-ink-400"> — {item.options.map((o) => o.name).join('، ')}</span>
              ) : null}
            </span>
            <span className="text-ink-500">{item.line_total}</span>
          </div>
        ))}
      </div>

      {order.delivery?.address && (
        <p className="mt-2 text-xs text-ink-500">📍 {order.delivery.address}</p>
      )}
      {order.customer_notes && (
        <p className="mt-2 rounded-lg bg-ink-50 px-3 py-2 text-xs text-ink-600">
          {t.orders.notes}: {order.customer_notes}
        </p>
      )}

      {order.tax_amount > 0 && (
        <div className="mt-3 space-y-1 border-t border-ink-100 pt-3 text-sm">
          <div className="flex justify-between text-ink-500">
            <span>{t.orders.subtotal}</span><span>{order.subtotal} {t.common.currency}</span>
          </div>
          {order.delivery_fee > 0 && (
            <div className="flex justify-between text-ink-500">
              <span>{t.orders.deliveryFee}</span><span>{order.delivery_fee} {t.common.currency}</span>
            </div>
          )}
          <div className="flex justify-between text-ink-500">
            <span>{t.orders.vat}</span><span>{order.tax_amount} {t.common.currency}</span>
          </div>
          <div className="flex justify-between font-bold text-ink-900">
            <span>{t.orders.total}</span><span>{order.total} {t.common.currency}</span>
          </div>
        </div>
      )}

      {order.invoice?.qr && <InvoiceBlock invoice={order.invoice} order={order} />}

      <Actions order={order} prep={prep} setPrep={setPrep} onUpdate={onUpdate} busy={busy} />
    </div>
  )
}

/**
 * The ZATCA simplified tax invoice for one order: the compliance QR (rendered
 * from the server's Base64 TLV), the seller's VAT details, and a print button
 * that opens a self-contained, RTL invoice ready for the printer.
 */
function InvoiceBlock({ invoice, order }: { invoice: Invoice; order: Order }) {
  const t = useT()
  const ref = useRef<HTMLDivElement>(null)

  const print = () => {
    const qrDataUrl = ref.current?.querySelector('canvas')?.toDataURL('image/png') ?? ''
    const w = window.open('', '_blank', 'width=460,height=720')
    if (!w) return

    const rate = invoice.tax_rate || 0
    const n = (v: number) => v.toFixed(2)
    const money = (v: number) => `${v.toFixed(2)} ${t.common.currency}`

    const line = (name: string, qty: number, taxable: number) => {
      const vat = taxable * rate / 100
      return `<tr><td class="name">${name}</td><td>${qty}</td><td>${n(taxable)}</td><td>${n(vat)}</td><td>${n(taxable + vat)}</td></tr>`
    }
    const rows =
      order.items.map((it) => line(it.name, it.quantity, it.line_total)).join('') +
      (order.delivery_fee > 0 ? line(t.orders.deliveryFee, 1, order.delivery_fee) : '')

    w.document.write(`<!doctype html><html dir="rtl" lang="ar"><head><meta charset="utf-8">
      <title>${t.orders.taxInvoice} ${invoice.number ?? order.reference}</title>
      <style>
        *{font-family:-apple-system,'Segoe UI',Tahoma,sans-serif;color:#1a1512;box-sizing:border-box}
        body{margin:0;padding:28px;font-size:12px}
        .wrap{max-width:520px;margin:0 auto}
        h1{font-size:17px;font-weight:800;text-align:center;margin:0 0 4px}
        .sub{text-align:center;color:#6b6b6b;font-size:11px;margin-bottom:16px}
        .logo{display:block;margin:0 auto 12px;max-height:76px}
        .seller{text-align:center;margin-bottom:6px}
        .seller .nm{font-weight:700;font-size:12.5px}
        .muted{color:#6b6b6b;font-size:11px}
        hr{border:0;border-top:1px solid #e6e6e6;margin:14px 0}
        .sec{font-weight:800;font-size:13px;margin:12px 0 8px}
        .kv{display:flex;justify-content:space-between;margin-bottom:4px}
        .kv .k{color:#6b6b6b}
        table{width:100%;border-collapse:collapse;margin:6px 0}
        th{font-size:9.5px;color:#6b6b6b;font-weight:700;padding:6px 2px;border-bottom:1px solid #ccc;text-align:center}
        td{font-size:10.5px;padding:8px 2px;border-bottom:1px solid #eee;text-align:center}
        td.name{text-align:right;font-weight:600}
        .tot .kv{font-size:12px}
        .grand{display:flex;justify-content:space-between;font-weight:800;font-size:14px;border-top:2px solid #1a1512;padding-top:8px;margin-top:6px}
        .qr{text-align:center;margin:18px 0}
        .foot{text-align:center;color:#9a9a9a;font-size:10px;margin-top:8px}
      </style></head><body><div class="wrap">
      <h1>فاتورة ضريبية مبسطة</h1>
      <div class="sub">${t.orders.taxInvoice}: ${invoice.number ?? order.reference} · ${invoice.issued_at ? new Date(invoice.issued_at).toLocaleDateString('ar') : ''}</div>
      ${invoice.logo ? `<img class="logo" src="${invoice.logo}" alt="logo">` : ''}
      <div class="seller">
        ${invoice.seller_name ? `<div class="nm">${invoice.seller_name}</div>` : ''}
        ${invoice.tax_number ? `<div class="muted">${t.orders.vatNumber}: ${invoice.tax_number}</div>` : ''}
        ${invoice.commercial_registration ? `<div class="muted">سجل تجاري رقم: ${invoice.commercial_registration}</div>` : ''}
        ${invoice.national_address ? `<div class="muted">العنوان: ${invoice.national_address}</div>` : ''}
      </div>
      <hr>
      ${order.customer?.name || order.customer?.phone ? `<div class="sec">معلومات العميل</div>
        ${order.customer?.name ? `<div class="kv"><span class="k">الاسم</span><span>${order.customer.name}</span></div>` : ''}
        ${order.customer?.phone ? `<div class="kv"><span class="k">الهاتف</span><span>${order.customer.phone}</span></div>` : ''}<hr>` : ''}
      <div class="sec">معلومات المنتجات</div>
      <table>
        <tr><th style="text-align:right">اسم المنتج</th><th>الكمية</th><th>الخاضع للضريبة</th><th>الضريبة</th><th>شامل الضريبة</th></tr>
        ${rows}
      </table>
      <div class="sec">تفاصيل الطلب</div>
      <div class="tot">
        <div class="kv"><span class="k">إجمالي المبلغ غير شامل الضريبة</span><span>${money(order.subtotal + order.delivery_fee)}</span></div>
        <div class="kv"><span class="k">إجمالي ضريبة القيمة المضافة ${rate}%</span><span>${money(order.tax_amount)}</span></div>
        <div class="grand"><span>الإجمالي</span><span>${money(order.total)}</span></div>
      </div>
      <hr>
      <div class="sec">طريقة الدفع</div>
      <div class="kv"><span class="k">الدفع عند الاستلام</span><span>${money(order.total)}</span></div>
      <div class="qr"><img src="${qrDataUrl}" width="150" height="150" alt="QR"></div>
      <div class="foot">© ${invoice.seller_name ?? ''} ${invoice.issued_at ? new Date(invoice.issued_at).getFullYear() : ''}</div>
      </div></body></html>`)
    w.document.close()
    w.focus()
    setTimeout(() => w.print(), 300)
  }

  return (
    <div ref={ref} className="mt-3 rounded-xl border border-ink-100 p-4">
      <div className="flex items-center justify-between">
        <span className="text-sm font-bold text-ink-900">{t.orders.taxInvoice}</span>
        <button
          onClick={print}
          className="inline-flex items-center gap-1.5 rounded-lg bg-ink-100 px-3 py-1.5 text-xs font-medium text-ink-800 hover:bg-ink-200"
        >
          <Printer className="size-3.5" /> {t.orders.printInvoice}
        </button>
      </div>
      <div className="mt-3 flex items-center gap-4">
        <QRCodeCanvas value={invoice.qr!} size={104} className="shrink-0 rounded-md" />
        <div className="min-w-0 space-y-0.5 text-xs text-ink-500">
          {invoice.seller_name && <div className="font-medium text-ink-800">{invoice.seller_name}</div>}
          {invoice.tax_number && <div>{t.orders.vatNumber}: {invoice.tax_number}</div>}
          {invoice.national_address && <div>{invoice.national_address}</div>}
        </div>
      </div>
    </div>
  )
}

function Actions({
  order,
  prep,
  setPrep,
  onUpdate,
  busy,
}: {
  order: Order
  prep: number
  setPrep: (n: number) => void
  onUpdate: (vars: { id: number; status: string; prep_minutes?: number; reason?: string }) => void
  busy: boolean
}) {
  const t = useT()
  const btn = 'rounded-lg px-4 py-2 text-sm font-semibold transition-colors disabled:opacity-50'

  if (order.status === 'placed') {
    return (
      <div className="mt-4 flex items-center gap-2">
        <div className="flex items-center gap-1.5 rounded-lg border border-ink-200 px-2 py-1.5">
          <input
            type="number"
            min={1}
            value={prep}
            onChange={(e) => setPrep(Number(e.target.value))}
            className="w-12 bg-transparent text-center text-sm outline-none"
          />
          <span className="text-xs text-ink-400">{t.common.minutes}</span>
        </div>
        <button
          disabled={busy}
          onClick={() => onUpdate({ id: order.id, status: 'accepted', prep_minutes: prep })}
          className={cn(btn, 'flex-1 bg-ink-900 text-white hover:bg-ink-800')}
        >
          {t.orders.accept}
        </button>
        <button
          disabled={busy}
          onClick={() => onUpdate({ id: order.id, status: 'rejected' })}
          className={cn(btn, 'bg-red-50 text-red-700 hover:bg-red-100')}
        >
          {t.orders.reject}
        </button>
      </div>
    )
  }

  const next: { status: string; label: string } | null =
    order.status === 'accepted'
      ? { status: 'preparing', label: t.orders.startPreparing }
      : order.status === 'preparing'
        ? { status: 'ready', label: t.orders.markReady }
        : order.status === 'ready'
          ? { status: 'completed', label: t.orders.complete }
          : null

  if (!next) return null

  return (
    <button
      disabled={busy}
      onClick={() => onUpdate({ id: order.id, status: next.status })}
      className={cn(btn, 'mt-4 w-full bg-ink-900 text-white hover:bg-ink-800')}
    >
      {next.label}
    </button>
  )
}
