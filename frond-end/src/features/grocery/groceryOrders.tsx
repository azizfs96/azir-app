import type { Dictionary } from '@/locales'
import type { OrderStatus } from '@/api/types'
import { cn } from '@/lib/cn'
import { useT } from '@/app/i18n'

/**
 * The grocery order lifecycle as the merchant sees it:
 *   placed (جديد) → preparing (جاري التحضير) → out_for_delivery (جاري التوصيل) → completed (تم الإيصال)
 * The server enforces this machine (SupermarketEngine::orderTransitions);
 * here we only decide which single button to show.
 */
export const GROCERY_COLUMNS = ['placed', 'preparing', 'out_for_delivery', 'completed'] as const
export type GroceryColumn = (typeof GROCERY_COLUMNS)[number]

/** Legacy statuses a grocery order can still carry (e.g. set by the driver app) fold into a column. */
export function groceryColumnOf(status: OrderStatus): GroceryColumn | null {
  switch (status) {
    case 'placed': return 'placed'
    case 'accepted':
    case 'preparing':
    case 'ready': return 'preparing'
    case 'out_for_delivery': return 'out_for_delivery'
    case 'completed': return 'completed'
    default: return null
  }
}

export function nextGroceryAction(status: OrderStatus, t: Dictionary): { status: string; label: string } | null {
  const o = t.grocery.orders
  switch (groceryColumnOf(status)) {
    case 'placed': return { status: 'preparing', label: o.startPreparing }
    case 'preparing': return { status: 'out_for_delivery', label: o.outForDelivery }
    case 'out_for_delivery': return { status: 'completed', label: o.delivered }
    default: return null
  }
}

const STYLE: Record<OrderStatus, string> = {
  placed: 'bg-warn-50 text-warn-600',
  accepted: 'bg-info-50 text-info-600',
  preparing: 'bg-info-50 text-info-600',
  ready: 'bg-info-50 text-info-600',
  out_for_delivery: 'bg-fresh-100 text-fresh-800',
  completed: 'bg-ink-100 text-ink-700',
  rejected: 'bg-bad-50 text-bad-600',
  cancelled: 'bg-bad-50 text-bad-600',
}

export function GroceryStatusBadge({ status }: { status: OrderStatus }) {
  const t = useT()
  return (
    <span className={cn('rounded-full px-2.5 py-0.5 text-xs font-semibold', STYLE[status])}>
      {t.grocery.orders.status[status]}
    </span>
  )
}
