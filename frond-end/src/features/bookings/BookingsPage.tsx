import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api, errorMessage } from '@/api/client'
import type { BookingStatus, MerchantBooking } from '@/api/types'
import { useT } from '@/app/i18n'
import { Card } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { StatusBadge } from '@/components/ui/StatusBadge'
import { EmptyState } from '@/components/shared/EmptyState'
import { PageHeader } from '@/components/shared/PageHeader'

function todayIso() {
  return new Date().toISOString().slice(0, 10)
}

/** Booking management (spec §13, §19). */
export function BookingsPage() {
  const t = useT()
  const queryClient = useQueryClient()
  const [date, setDate] = useState(todayIso())
  const [error, setError] = useState<string | null>(null)

  const { data, isLoading } = useQuery({
    queryKey: ['merchant-bookings', date],
    queryFn: async () =>
      (await api.get<{ data: { data: MerchantBooking[] } }>('/merchant/bookings', {
        params: { date },
      })).data.data,
  })

  const changeStatus = useMutation({
    mutationFn: async ({ id, status }: { id: number; status: BookingStatus }) =>
      (await api.post(`/merchant/bookings/${id}/status`, { status })).data,
    onSuccess: () => {
      setError(null)
      void queryClient.invalidateQueries({ queryKey: ['merchant-bookings'] })
      void queryClient.invalidateQueries({ queryKey: ['dashboard'] })
    },
    // The state machine rejects invalid transitions server-side; surface why.
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const bookings = data?.data ?? []

  return (
    <>
      <PageHeader
        title={t.bookings.title}
        action={
          <input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="h-9 rounded-lg border border-ink-200 bg-white px-3 text-sm text-ink-900"
          />
        }
      />

      {error && (
        <div className="mb-4 rounded-lg border border-bad-600/25 bg-bad-50 px-4 py-2.5 text-sm text-bad-600">
          {error}
        </div>
      )}

      <Card>
        {isLoading ? (
          <p className="px-5 py-8 text-sm text-ink-500">{t.common.loading}</p>
        ) : bookings.length === 0 ? (
          <EmptyState title={t.bookings.empty} />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-ink-200 text-start text-xs text-ink-500">
                  <th className="px-5 py-2.5 text-start font-medium">{t.bookings.time}</th>
                  <th className="px-5 py-2.5 text-start font-medium">{t.bookings.customer}</th>
                  <th className="px-5 py-2.5 text-start font-medium">{t.bookings.service}</th>
                  <th className="px-5 py-2.5 text-start font-medium">{t.bookings.staff}</th>
                  <th className="px-5 py-2.5 text-start font-medium">{t.bookings.price}</th>
                  <th className="px-5 py-2.5 text-start font-medium">{t.bookings.status}</th>
                  <th className="px-5 py-2.5 text-start font-medium">{t.bookings.actions}</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-ink-200">
                {bookings.map((booking) => (
                  <tr key={booking.id} className="hover:bg-ink-50">
                    <td className="whitespace-nowrap px-5 py-3 font-medium tabular-nums">
                      {booking.time}
                    </td>
                    <td className="px-5 py-3">
                      <div className="text-ink-900">{booking.customer.name ?? '—'}</div>
                      {/* The merchant needs this to call about a late arrival. */}
                      <div className="text-xs text-ink-400" dir="ltr">{booking.customer.phone}</div>
                    </td>
                    <td className="px-5 py-3 text-ink-700">{booking.service ?? '—'}</td>
                    <td className="px-5 py-3 text-ink-500">{booking.staff ?? '—'}</td>
                    <td className="whitespace-nowrap px-5 py-3 tabular-nums text-ink-700">
                      {booking.price} {t.common.currency}
                    </td>
                    <td className="px-5 py-3"><StatusBadge status={booking.status} /></td>
                    <td className="px-5 py-3">
                      {/*
                        Only transitions the state machine actually permits are
                        rendered — the server tells us which (spec §19), so the
                        UI never offers a button that would 422.
                      */}
                      <div className="flex gap-1.5">
                        {booking.allowed_transitions
                          .filter((next) => next !== 'cancelled')
                          .map((next) => (
                            <Button
                              key={next}
                              size="sm"
                              variant="secondary"
                              loading={changeStatus.isPending}
                              onClick={() => changeStatus.mutate({ id: booking.id, status: next })}
                            >
                              {t.status[next]}
                            </Button>
                          ))}
                      </div>
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
