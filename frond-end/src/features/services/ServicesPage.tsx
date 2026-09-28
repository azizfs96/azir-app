import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, Scissors, Trash2 } from 'lucide-react'
import { api, errorMessage } from '@/api/client'
import type { Service } from '@/api/types'
import { useT } from '@/app/i18n'
import { Card } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Modal } from '@/components/shared/Modal'
import { EmptyState } from '@/components/shared/EmptyState'
import { PageHeader } from '@/components/shared/PageHeader'

/** Service management (spec §14). */
export function ServicesPage() {
  const t = useT()
  const queryClient = useQueryClient()
  const [open, setOpen] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [form, setForm] = useState({ name_ar: '', name_en: '', price: '', duration_minutes: '' })

  const { data, isLoading } = useQuery({
    queryKey: ['services'],
    queryFn: async () => (await api.get<{ data: Service[] }>('/merchant/services')).data.data,
  })

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ['services'] })
    // Adding the first service can unblock publishing (spec §11).
    void queryClient.invalidateQueries({ queryKey: ['onboarding'] })
  }

  const create = useMutation({
    mutationFn: async () => (await api.post('/merchant/services', {
      name_ar: form.name_ar,
      name_en: form.name_en || null,
      price: Number(form.price),
      duration_minutes: Number(form.duration_minutes),
    })).data,
    onSuccess: () => {
      setOpen(false)
      setForm({ name_ar: '', name_en: '', price: '', duration_minutes: '' })
      invalidate()
    },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const remove = useMutation({
    mutationFn: async (id: number) => (await api.delete(`/merchant/services/${id}`)).data,
    onSuccess: invalidate,
  })

  const services = data ?? []

  return (
    <>
      <PageHeader
        title={t.services.title}
        action={
          <Button onClick={() => { setError(null); setOpen(true) }}>
            <Plus className="size-4" />
            {t.services.add}
          </Button>
        }
      />

      <Card>
        {isLoading ? (
          <p className="px-5 py-8 text-sm text-ink-500">{t.common.loading}</p>
        ) : services.length === 0 ? (
          <EmptyState
            icon={<Scissors className="size-8" />}
            title={t.services.empty}
            hint={t.services.emptyHint}
            action={<Button onClick={() => setOpen(true)}>{t.services.add}</Button>}
          />
        ) : (
          <ul className="divide-y divide-ink-200">
            {services.map((service) => (
              <li key={service.id} className="flex items-center gap-4 px-5 py-3.5">
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-medium text-ink-900">{service.name}</div>
                  <div className="mt-0.5 text-xs text-ink-500">
                    {service.duration_minutes} {t.common.minutes}
                  </div>
                </div>
                <div className="shrink-0 text-sm font-medium tabular-nums text-ink-900">
                  {service.price} {t.common.currency}
                </div>
                <button
                  onClick={() => confirm(t.services.deleteConfirm) && remove.mutate(service.id)}
                  aria-label={t.common.delete}
                  className="shrink-0 rounded-md p-1.5 text-ink-400 hover:bg-bad-50 hover:text-bad-600"
                >
                  <Trash2 className="size-4" />
                </button>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Modal
        open={open}
        onClose={() => setOpen(false)}
        title={t.services.add}
        footer={
          <>
            <Button variant="secondary" onClick={() => setOpen(false)}>{t.common.cancel}</Button>
            <Button loading={create.isPending} onClick={() => create.mutate()}>
              {t.common.save}
            </Button>
          </>
        }
      >
        <div className="space-y-4">
          {error && <p className="text-sm text-bad-600">{error}</p>}
          <Input
            label={t.services.nameAr}
            value={form.name_ar}
            onChange={(e) => setForm({ ...form, name_ar: e.target.value })}
          />
          <Input
            label={t.services.nameEn}
            value={form.name_en}
            onChange={(e) => setForm({ ...form, name_en: e.target.value })}
          />
          <div className="grid grid-cols-2 gap-3">
            <Input
              label={t.services.price}
              type="number"
              min={0}
              value={form.price}
              onChange={(e) => setForm({ ...form, price: e.target.value })}
            />
            <Input
              label={t.services.duration}
              type="number"
              min={5}
              step={5}
              value={form.duration_minutes}
              onChange={(e) => setForm({ ...form, duration_minutes: e.target.value })}
            />
          </div>
        </div>
      </Modal>
    </>
  )
}
