import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, CalendarOff, Trash2 } from 'lucide-react'
import { api, errorMessage } from '@/api/client'
import type { AffectedBooking, TimeOffEntry } from '@/api/types'
import { useI18n } from '@/app/i18n'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Modal } from '@/components/shared/Modal'
import { TimeSelect } from '@/components/shared/WeeklyHours'

/**
 * ============================================================================
 * BLOCK TIME FOR ONE DATE — "an errand today from 6 to 7"
 *
 * The weekly editor answers "when do I normally work"; this answers "except
 * THIS Thursday". The engine has honoured these blocks all along — this modal
 * is the door the audit found missing.
 *
 * If bookings already sit inside the window they are listed loudly after
 * saving, because blocking time never cancels a promise made to a customer —
 * that call belongs to the merchant.
 * ============================================================================
 */
export function TimeOffModal({ staffId, staffName, onClose }: {
  staffId: number
  staffName: string
  onClose: () => void
}) {
  const { t, locale } = useI18n()
  const s = t.timeOff
  const queryClient = useQueryClient()

  const today = new Date().toISOString().slice(0, 10)

  const [date, setDate] = useState(today)
  const [from, setFrom] = useState('18:00')
  const [to, setTo] = useState('19:00')
  const [allDay, setAllDay] = useState(false)
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [affected, setAffected] = useState<AffectedBooking[]>([])

  const { data: entries } = useQuery({
    queryKey: ['time-off', staffId],
    queryFn: async () =>
      (await api.get<{ data: TimeOffEntry[] }>('/merchant/time-off', {
        params: { staff_id: staffId },
      })).data.data,
  })

  const invalidate = () => void queryClient.invalidateQueries({ queryKey: ['time-off', staffId] })

  const create = useMutation({
    mutationFn: async () =>
      (await api.post('/merchant/time-off', {
        staff_id: staffId,
        date,
        // 00:00 → 00:00 is the server's "whole day" convention.
        from: allDay ? '00:00' : from,
        to: allDay ? '00:00' : to,
        reason: reason || null,
      })).data,
    onSuccess: (data: { affected_bookings: AffectedBooking[] }) => {
      setError(null)
      setAffected(data.affected_bookings ?? [])
      invalidate()
    },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const remove = useMutation({
    mutationFn: async (id: number) => (await api.delete(`/merchant/time-off/${id}`)).data,
    onSuccess: invalidate,
  })

  /*
   * Render times from the ISO STRING, never through new Date(): the server
   * already sends store-local time ("…T18:00:00+03:00"), and Date() would
   * re-shift it into the viewing DEVICE's timezone — a merchant checking the
   * dashboard while travelling saw their 6 PM block as 8 AM.
   */
  const dayFmt = new Intl.DateTimeFormat(locale === 'en' ? 'en' : 'ar', {
    weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC',
  })

  const localStamp = (iso: string) => {
    const [datePart, timePart] = iso.slice(0, 16).split('T')
    const [h, m] = timePart.split(':').map(Number)
    const suffix = h < 12 ? (locale === 'en' ? 'AM' : 'ص') : (locale === 'en' ? 'PM' : 'م')
    const hour = h % 12 === 0 ? 12 : h % 12

    return {
      day: dayFmt.format(new Date(`${datePart}T00:00:00Z`)),
      time: `${hour}:${String(m).padStart(2, '0')} ${suffix}`,
    }
  }

  const fmtRange = (entry: TimeOffEntry) => {
    const start = localStamp(entry.starts_at)
    const end = localStamp(entry.ends_at)

    return `${start.day}، ${start.time} — ${end.time}`
  }

  return (
    <Modal
      open
      onClose={onClose}
      title={`${s.title} — ${staffName}`}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>{t.common.cancel}</Button>
          <Button loading={create.isPending} onClick={() => create.mutate()}>{s.add}</Button>
        </>
      }
    >
      <div className="space-y-4">
        <p className="text-xs text-ink-500">{s.hint}</p>

        {error && (
          <div className="rounded-lg border border-bad-600/25 bg-bad-50 px-3 py-2 text-sm text-bad-600">
            {error}
          </div>
        )}

        {/* The post-save warning the whole feature exists to surface. */}
        {create.isSuccess && (
          affected.length > 0 ? (
            <div className="rounded-lg border border-warn-600/25 bg-warn-50 px-3 py-2.5 text-sm">
              <p className="flex items-center gap-1.5 font-medium text-warn-600">
                <AlertTriangle className="size-4 shrink-0" />
                {s.affectedTitle}
              </p>
              <p className="mt-1 text-xs text-ink-500">{s.affectedHint}</p>
              <ul className="mt-1.5 space-y-1 text-xs text-ink-700">
                {affected.map((booking) => (
                  <li key={booking.id}>
                    {`${localStamp(booking.starts_at).day}، ${localStamp(booking.starts_at).time}`}
                    {booking.customer ? ` · ${booking.customer}` : ''}
                    {booking.service ? ` · ${booking.service}` : ''}
                    <span className="text-ink-400"> ({booking.reference})</span>
                  </li>
                ))}
              </ul>
            </div>
          ) : (
            <div className="rounded-lg border border-ok-600/25 bg-ok-50 px-3 py-2 text-sm text-ok-600">
              {s.blocked}
            </div>
          )
        )}

        <label className="block">
          <span className="mb-1.5 block text-[13px] font-medium text-ink-700">{s.date}</span>
          <input
            type="date"
            min={today}
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="h-10 w-full rounded-lg border border-ink-200 bg-white px-3 text-sm"
          />
        </label>

        <div className="flex flex-wrap items-end gap-3">
          {!allDay && (
            <>
              <label className="block">
                <span className="mb-1.5 block text-[13px] font-medium text-ink-700">{s.from}</span>
                <TimeSelect value={from} onChange={setFrom} />
              </label>
              <label className="block">
                <span className="mb-1.5 block text-[13px] font-medium text-ink-700">{s.to}</span>
                <TimeSelect value={to} onChange={setTo} />
              </label>
            </>
          )}

          <label className="flex h-10 cursor-pointer items-center gap-2 text-sm text-ink-700">
            <input
              type="checkbox"
              checked={allDay}
              onChange={(e) => setAllDay(e.target.checked)}
              className="size-4 rounded border-ink-300"
            />
            {s.allDay}
          </label>
        </div>

        <Input
          label={s.reason}
          value={reason}
          placeholder={s.reasonPlaceholder}
          onChange={(e) => setReason(e.target.value)}
        />

        <div>
          <p className="mb-1.5 text-[13px] font-medium text-ink-700">{s.upcoming}</p>
          {(entries ?? []).length === 0 ? (
            <p className="flex items-center gap-2 text-sm text-ink-400">
              <CalendarOff className="size-4" />
              {s.none}
            </p>
          ) : (
            <ul className="divide-y divide-ink-100 rounded-lg border border-ink-200">
              {(entries ?? []).map((entry) => (
                <li key={entry.id} className="flex items-center gap-2 px-3 py-2 text-sm">
                  <span className="text-ink-700">{fmtRange(entry)}</span>
                  {entry.reason && <span className="text-xs text-ink-400">· {entry.reason}</span>}
                  <button
                    onClick={() => remove.mutate(entry.id)}
                    aria-label={t.common.delete}
                    className="ms-auto rounded-md p-1 text-ink-400 hover:bg-bad-50 hover:text-bad-600"
                  >
                    <Trash2 className="size-3.5" />
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </Modal>
  )
}
