import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api, errorMessage } from '@/api/client'
import type { BookingSettings } from '@/api/types'
import { useT } from '@/app/i18n'
import { Card, CardHeader } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { PageHeader } from '@/components/shared/PageHeader'
import { StoreMediaPanel } from './StoreMediaPanel'
import { useStoreType } from '@/features/menu/useStoreType'
import { cn } from '@/lib/cn'

function Toggle({
  label, hint, checked, onChange,
}: { label: string; hint?: string; checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <div className="flex items-start justify-between gap-4 px-5 py-3.5">
      <div className="min-w-0">
        <div className="text-sm text-ink-900">{label}</div>
        {hint && <div className="mt-0.5 text-xs text-ink-500">{hint}</div>}
      </div>
      <button
        role="switch"
        aria-checked={checked}
        aria-label={label}
        onClick={() => onChange(!checked)}
        className={cn(
          'relative h-5 w-9 shrink-0 rounded-full transition-colors',
          checked ? 'bg-ink-900' : 'bg-ink-200',
        )}
      >
        {/* start-/end- keep the knob on the correct side in RTL (spec §33). */}
        <span className={cn(
          'absolute top-0.5 size-4 rounded-full bg-white transition-all',
          checked ? 'start-[18px]' : 'start-0.5',
        )} />
      </button>
    </div>
  )
}

/**
 * Booking settings (spec §10, §21, §22).
 *
 * This is the "50 technical settings" surface deliberately kept OUT of
 * onboarding (spec §11). Changing staff_selection here immediately changes the
 * customer app's flow — no release required (§43).
 */
export function SettingsPage() {
  const t = useT()
  const { isRestaurant } = useStoreType()
  const queryClient = useQueryClient()
  const [draft, setDraft] = useState<BookingSettings | null>(null)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const { data } = useQuery({
    queryKey: ['booking-settings'],
    queryFn: async () => (await api.get<{
      settings: BookingSettings
      online_payment_available: boolean
    }>('/merchant/settings/booking')).data,
  })

  useEffect(() => {
    if (data?.settings) setDraft(data.settings)
  }, [data])

  const save = useMutation({
    mutationFn: async (payload: Partial<BookingSettings>) =>
      (await api.patch('/merchant/settings/booking', payload)).data,
    onSuccess: () => {
      setError(null)
      setSaved(true)
      setTimeout(() => setSaved(false), 2000)
      void queryClient.invalidateQueries({ queryKey: ['booking-settings'] })
    },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  if (!draft) return <p className="text-sm text-ink-500">{t.common.loading}</p>

  const set = <K extends keyof BookingSettings>(key: K, value: BookingSettings[K]) =>
    setDraft({ ...draft, [key]: value })

  return (
    <>
      <PageHeader
        title={t.settings.title}
        action={
          <Button loading={save.isPending} onClick={() => save.mutate(draft)}>
            {saved ? t.settings.saved : t.common.save}
          </Button>
        }
      />

      {error && (
        <div className="mb-4 rounded-lg border border-bad-600/25 bg-bad-50 px-4 py-2.5 text-sm text-bad-600">
          {error}
        </div>
      )}

      {/* Payments are descoped for the MVP — say so rather than showing a
          toggle the API will reject (see SettingsController). */}
      {data && !data.online_payment_available && (
        <div className="mb-5 rounded-[10px] border border-ink-200 bg-white px-4 py-3 text-sm text-ink-500">
          {t.settings.paymentUnavailable}
        </div>
      )}

      <div className="space-y-5">
        <StoreMediaPanel />

        {isRestaurant && (
          <>
            <Card>
              <CardHeader title={t.settings.ordersTitle} />
              <div className="divide-y divide-ink-200">
                <Toggle label={t.settings.orderPickup} checked={draft.order_pickup}
                  onChange={(v) => set('order_pickup', v)} />
                <Toggle label={t.settings.orderDineIn} checked={draft.order_dine_in}
                  onChange={(v) => set('order_dine_in', v)} />
                <Toggle label={t.settings.orderDelivery} checked={draft.order_delivery}
                  onChange={(v) => set('order_delivery', v)} />
                <Toggle label={t.settings.orderCurbside} checked={draft.order_curbside}
                  onChange={(v) => set('order_curbside', v)} />
                <Toggle label={t.settings.autoAccept} hint={t.settings.autoAcceptHint}
                  checked={draft.auto_accept_orders} onChange={(v) => set('auto_accept_orders', v)} />
              </div>
              <div className="grid gap-4 px-5 py-5 sm:grid-cols-2">
                {draft.order_delivery && (
                  <>
                    <Input label={t.settings.deliveryFee} type="number" min={0} step="0.01"
                      value={draft.delivery_fee}
                      onChange={(e) => set('delivery_fee', Number(e.target.value))} />
                    <Input label={t.settings.deliveryMinOrder} type="number" min={0} step="0.01"
                      value={draft.delivery_min_order}
                      onChange={(e) => set('delivery_min_order', Number(e.target.value))} />
                  </>
                )}
                <Input label={t.settings.prepMinutes} type="number" min={0} max={240}
                  value={draft.default_prep_minutes}
                  onChange={(e) => set('default_prep_minutes', Number(e.target.value))} />
              </div>
            </Card>

            <Card>
              <CardHeader title={t.settings.invoicingTitle} />
              <div className="divide-y divide-ink-200">
                <Toggle label={t.settings.taxEnabled} hint={t.settings.taxEnabledHint}
                  checked={draft.tax_enabled} onChange={(v) => set('tax_enabled', v)} />
              </div>
              {draft.tax_enabled && (
                <div className="grid gap-4 px-5 py-5 sm:grid-cols-2">
                  <Input label={t.settings.taxRate} type="number" min={0} max={100} step="0.01"
                    value={draft.tax_rate}
                    onChange={(e) => set('tax_rate', Number(e.target.value))} />
                  <Input label={t.settings.taxNumber} hint={t.settings.taxNumberHint}
                    value={draft.tax_number ?? ''}
                    onChange={(e) => set('tax_number', e.target.value)} />
                  <Input label={t.settings.legalName} hint={t.settings.legalNameHint}
                    value={draft.legal_name ?? ''}
                    onChange={(e) => set('legal_name', e.target.value)} />
                  <Input label={t.settings.nationalAddress}
                    value={draft.national_address ?? ''}
                    onChange={(e) => set('national_address', e.target.value)} />
                </div>
              )}
            </Card>
          </>
        )}

        <Card>
          <CardHeader title={t.settings.title} />
          <div className="divide-y divide-ink-200">
            <Toggle
              label={t.settings.staffSelection}
              hint={t.settings.staffSelectionHint}
              checked={draft.staff_selection}
              onChange={(v) => set('staff_selection', v)}
            />
            <Toggle
              label={t.settings.branchSelection}
              checked={draft.branch_selection}
              onChange={(v) => set('branch_selection', v)}
            />
            <Toggle
              label={t.settings.customerNotes}
              checked={draft.customer_notes}
              onChange={(v) => set('customer_notes', v)}
            />
            <Toggle
              label={t.settings.autoConfirm}
              checked={draft.auto_confirm}
              onChange={(v) => set('auto_confirm', v)}
            />
            <Toggle
              label={t.settings.allowCancellation}
              checked={draft.allow_cancellation}
              onChange={(v) => set('allow_cancellation', v)}
            />
            <Toggle
              label={t.settings.allowRescheduling}
              checked={draft.allow_rescheduling}
              onChange={(v) => set('allow_rescheduling', v)}
            />
          </div>
        </Card>

        <Card>
          <div className="grid gap-4 px-5 py-5 sm:grid-cols-2">
            <Input
              label={t.settings.cancellationDeadline}
              type="number" min={0} max={168}
              value={draft.cancellation_deadline_hours}
              onChange={(e) => set('cancellation_deadline_hours', Number(e.target.value))}
            />
            <Input
              label={t.settings.minLeadTime}
              type="number" min={0}
              value={draft.min_lead_time_minutes}
              onChange={(e) => set('min_lead_time_minutes', Number(e.target.value))}
            />
            <Input
              label={t.settings.maxAdvance}
              type="number" min={1} max={365}
              value={draft.max_advance_days}
              onChange={(e) => set('max_advance_days', Number(e.target.value))}
            />
            <Input
              label={t.settings.reminder}
              type="number" min={1} max={168}
              value={draft.reminder_hours_before}
              onChange={(e) => set('reminder_hours_before', Number(e.target.value))}
            />
          </div>
        </Card>
      </div>
    </>
  )
}
