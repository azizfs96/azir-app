import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Users } from 'lucide-react'
import { api } from '@/api/client'
import { useT } from '@/app/i18n'
import { Card } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { EmptyState } from '@/components/shared/EmptyState'
import { PageHeader } from '@/components/shared/PageHeader'

interface MerchantCustomer {
  customer_id: number | null
  name: string | null
  phone: string | null
  total_bookings: number
  completed: number
  no_shows: number
  cancelled: number
  total_spent: number
  last_visit: string | null
}

/**
 * Merchant customers (spec §12).
 *
 * Derived from bookings, not ownership — a customer belongs to the platform,
 * and a merchant only ever sees the people who actually came to them (§46).
 */
export function CustomersPage() {
  const t = useT()
  const [search, setSearch] = useState('')

  const { data, isLoading } = useQuery({
    queryKey: ['merchant-customers', search],
    queryFn: async () => (await api.get<{ data: { data: MerchantCustomer[] } }>(
      '/merchant/customers',
      { params: search ? { search } : {} },
    )).data.data.data,
  })

  const customers = data ?? []

  return (
    <>
      <PageHeader
        title={t.customersPage.title}
        action={
          <div className="w-56">
            <Input
              placeholder={t.customersPage.search}
              value={search}
              onChange={(e) => setSearch(e.target.value)}
            />
          </div>
        }
      />

      <Card>
        {isLoading ? (
          <p className="px-5 py-8 text-sm text-ink-500">{t.common.loading}</p>
        ) : customers.length === 0 ? (
          <EmptyState
            icon={<Users className="size-8" />}
            title={t.customersPage.empty}
            hint={t.customersPage.emptyHint}
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-ink-200 text-xs text-ink-500">
                  <th className="px-5 py-2.5 text-start font-medium">{t.customersPage.name}</th>
                  <th className="px-5 py-2.5 text-start font-medium">{t.customersPage.bookings}</th>
                  <th className="px-5 py-2.5 text-start font-medium">{t.customersPage.completed}</th>
                  <th className="px-5 py-2.5 text-start font-medium">{t.customersPage.noShows}</th>
                  <th className="px-5 py-2.5 text-start font-medium">{t.customersPage.spent}</th>
                  <th className="px-5 py-2.5 text-start font-medium">{t.customersPage.lastVisit}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-ink-200">
                {customers.map((customer, i) => (
                  <tr key={customer.customer_id ?? `guest-${i}`} className="hover:bg-ink-50">
                    <td className="px-5 py-3">
                      <div className="text-ink-900">{customer.name ?? '—'}</div>
                      <div className="text-xs text-ink-400" dir="ltr">{customer.phone}</div>
                    </td>
                    <td className="px-5 py-3 tabular-nums text-ink-700">{customer.total_bookings}</td>
                    <td className="px-5 py-3 tabular-nums text-ok-600">{customer.completed}</td>
                    <td className={`px-5 py-3 tabular-nums ${customer.no_shows > 0 ? 'text-bad-600' : 'text-ink-400'}`}>
                      {/* A merchant genuinely weighs this before giving someone
                          a prime Thursday-evening slot. */}
                      {customer.no_shows}
                    </td>
                    <td className="whitespace-nowrap px-5 py-3 tabular-nums text-ink-900">
                      {customer.total_spent.toLocaleString()} {t.common.currency}
                    </td>
                    <td className="whitespace-nowrap px-5 py-3 text-ink-500">
                      {customer.last_visit ? customer.last_visit.slice(0, 10) : '—'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
    </>
  )
}
