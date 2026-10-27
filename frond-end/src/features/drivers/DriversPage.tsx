import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Bike, Pencil, Plus, Trash2 } from 'lucide-react'
import { api, errorMessage, type ApiError } from '@/api/client'
import type { Driver } from '@/api/types'
import { useT } from '@/app/i18n'
import { Card, CardHeader } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Modal } from '@/components/shared/Modal'
import { EmptyState } from '@/components/shared/EmptyState'
import { PageHeader } from '@/components/shared/PageHeader'
import { cn } from '@/lib/cn'

/**
 * Delivery drivers — the accounts for the "Easy App Driver" app.
 *
 * Creating a driver creates their login (phone + password). The password is
 * only ever typed here; the API stores a hash, so "edit" can set a new one but
 * never shows the old one.
 */
type Form = { name: string; phone: string; password: string; vehicle: string }
const EMPTY: Form = { name: '', phone: '', password: '', vehicle: '' }

export function DriversPage() {
  const t = useT()
  const queryClient = useQueryClient()

  const [editing, setEditing] = useState<Driver | null | 'new'>(null)
  const [form, setForm] = useState<Form>(EMPTY)
  const [error, setError] = useState<string | null>(null)
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})

  const { data, isLoading } = useQuery({
    queryKey: ['drivers'],
    queryFn: async () => (await api.get<{ data: Driver[] }>('/merchant/drivers')).data.data,
    refetchInterval: 30000,
  })

  const invalidate = () => void queryClient.invalidateQueries({ queryKey: ['drivers'] })

  const onError = (err: unknown) => {
    const errors = (err as { response?: { data?: ApiError } }).response?.data?.errors
    if (errors) setFieldErrors(Object.fromEntries(Object.entries(errors).map(([k, v]) => [k, v[0]])))
    else setError(errorMessage(err, t.common.error))
  }

  const openNew = () => {
    setForm(EMPTY); setError(null); setFieldErrors({}); setEditing('new')
  }
  const openEdit = (d: Driver) => {
    setForm({ name: d.name, phone: d.phone, password: '', vehicle: d.vehicle ?? '' })
    setError(null); setFieldErrors({}); setEditing(d)
  }
  const close = () => setEditing(null)

  const save = useMutation({
    mutationFn: async () => {
      const body = {
        name: form.name,
        phone: form.phone,
        vehicle: form.vehicle || null,
        ...(form.password ? { password: form.password } : {}),
      }
      if (editing === 'new') return (await api.post('/merchant/drivers', body)).data
      return (await api.put(`/merchant/drivers/${(editing as Driver).id}`, body)).data
    },
    onSuccess: () => { close(); invalidate() },
    onError,
  })

  const toggleActive = useMutation({
    mutationFn: async (d: Driver) => (await api.put(`/merchant/drivers/${d.id}`, { is_active: !d.is_active })).data,
    onSuccess: invalidate,
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const remove = useMutation({
    mutationFn: async (id: number) => (await api.delete(`/merchant/drivers/${id}`)).data,
    onSuccess: invalidate,
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const drivers = data ?? []

  return (
    <>
      <PageHeader
        title={t.driversPage.title}
        subtitle={t.driversPage.subtitle}
        action={
          <Button onClick={openNew}>
            <Plus className="size-4" />
            {t.driversPage.add}
          </Button>
        }
      />

      {error && (
        <div className="mb-4 rounded-lg border border-bad-600/25 bg-bad-50 px-4 py-2.5 text-sm text-bad-600">
          {error}
        </div>
      )}

      {isLoading ? (
        <p className="text-sm text-ink-500">{t.common.loading}</p>
      ) : drivers.length === 0 ? (
        <Card>
          <EmptyState
            icon={<Bike className="size-8" />}
            title={t.driversPage.empty}
            hint={t.driversPage.emptyHint}
            action={<Button onClick={openNew}>{t.driversPage.add}</Button>}
          />
        </Card>
      ) : (
        <div className="space-y-4">
          {drivers.map((d) => (
            <Card key={d.id}>
              <CardHeader
                title={
                  <span className="flex items-center gap-2">
                    {d.name}
                    <span
                      className={cn(
                        'rounded-md px-2 py-0.5 text-xs font-normal',
                        d.is_active ? 'bg-ok-50 text-ok-600' : 'bg-ink-100 text-ink-500',
                      )}
                    >
                      {d.is_active ? t.driversPage.active : t.driversPage.inactive}
                    </span>
                    {d.active_orders_count ? (
                      <span className="rounded-md bg-info-50 px-2 py-0.5 text-xs font-normal text-info-600">
                        {t.driversPage.onDelivery(d.active_orders_count)}
                      </span>
                    ) : null}
                  </span>
                }
                action={
                  <div className="flex items-center gap-2">
                    <Button size="sm" variant="secondary" onClick={() => toggleActive.mutate(d)}
                      loading={toggleActive.isPending && toggleActive.variables?.id === d.id}>
                      {d.is_active ? t.driversPage.deactivate : t.driversPage.activate}
                    </Button>
                    <button
                      onClick={() => openEdit(d)}
                      aria-label={t.common.edit}
                      className="rounded-md p-1.5 text-ink-400 hover:bg-ink-100 hover:text-ink-900"
                    >
                      <Pencil className="size-4" />
                    </button>
                    <button
                      onClick={() => confirm(t.driversPage.deleteConfirm) && remove.mutate(d.id)}
                      aria-label={t.common.delete}
                      className="rounded-md p-1.5 text-ink-400 hover:bg-bad-50 hover:text-bad-600"
                    >
                      <Trash2 className="size-4" />
                    </button>
                  </div>
                }
              />
              <div className="flex flex-wrap items-center gap-x-5 gap-y-1 px-5 py-3 text-sm text-ink-500">
                <span dir="ltr">{d.phone}</span>
                {d.vehicle && <span>{d.vehicle}</span>}
                {d.last_location && (
                  <span className={cn('text-xs', d.last_location.fresh ? 'text-ok-600' : 'text-ink-400')}>
                    {d.last_location.fresh ? t.driversPage.locationLive : t.driversPage.locationStale}
                    {' · '}
                    {new Date(d.last_location.located_at).toLocaleTimeString('ar', { hour: '2-digit', minute: '2-digit' })}
                  </span>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}

      <Modal
        open={editing !== null}
        onClose={close}
        title={editing === 'new' ? t.driversPage.add : t.driversPage.edit}
        footer={
          <>
            <Button variant="secondary" onClick={close}>{t.common.cancel}</Button>
            <Button loading={save.isPending} onClick={() => { setFieldErrors({}); save.mutate() }}>
              {t.common.save}
            </Button>
          </>
        }
      >
        <div className="space-y-4">
          <Input label={t.driversPage.name} value={form.name} error={fieldErrors.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })} />
          <Input label={t.driversPage.phone} type="tel" inputMode="tel" dir="ltr" placeholder="05XXXXXXXX"
            value={form.phone} error={fieldErrors.phone} hint={t.driversPage.phoneHint}
            onChange={(e) => setForm({ ...form, phone: e.target.value })} />
          <Input
            label={t.driversPage.password}
            type="password"
            autoComplete="new-password"
            value={form.password}
            error={fieldErrors.password}
            hint={editing === 'new' ? t.driversPage.passwordHint : t.driversPage.passwordEditHint}
            onChange={(e) => setForm({ ...form, password: e.target.value })}
          />
          <Input label={t.driversPage.vehicle} value={form.vehicle} placeholder={t.driversPage.vehiclePlaceholder}
            onChange={(e) => setForm({ ...form, vehicle: e.target.value })} />
        </div>
      </Modal>
    </>
  )
}
