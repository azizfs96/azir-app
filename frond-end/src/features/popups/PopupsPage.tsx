import { useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ImagePlus, Megaphone, Trash2 } from 'lucide-react'
import { api, errorMessage, mediaUrl } from '@/api/client'
import { useT } from '@/app/i18n'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { cn } from '@/lib/cn'

/**
 * POP-UP ADS — the merchant's "own app" moment. An image (optionally titled)
 * that customers see when they open THIS store in the app, scheduled and
 * shown at a chosen frequency. Server: /merchant/popups (+ /image upload).
 */

type Frequency = 'every_visit' | 'once_per_day' | 'once'

interface Popup {
  id: number
  image: string | null
  title_ar: string | null
  title_en: string | null
  frequency: Frequency
  starts_at: string | null
  ends_at: string | null
  is_active: boolean
  sort_order: number
}

const FREQUENCIES: Frequency[] = ['every_visit', 'once_per_day', 'once']

/** ISO → value for <input type="datetime-local"> (local time, minutes). */
function toLocalInput(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export function PopupsPage() {
  const t = useT()
  const qc = useQueryClient()
  const [error, setError] = useState<string | null>(null)

  const { data: popups, isLoading, isError } = useQuery({
    queryKey: ['merchant-popups'],
    queryFn: async () => (await api.get<{ data: Popup[] }>('/merchant/popups')).data.data,
  })

  const invalidate = () => void qc.invalidateQueries({ queryKey: ['merchant-popups'] })
  const fail = (err: unknown) => setError(errorMessage(err, t.common.error))

  const create = useMutation({
    mutationFn: async () => (await api.post<Popup>('/merchant/popups', { frequency: 'once_per_day' })).data,
    onSuccess: invalidate,
    onError: fail,
  })

  return (
    <div>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-ink-900">{t.popups.title}</h1>
          <p className="mt-1 text-sm text-ink-500">{t.popups.subtitle}</p>
        </div>
        <Button onClick={() => create.mutate()} loading={create.isPending}>
          {t.popups.add}
        </Button>
      </div>

      {error && (
        <p className="mb-4 rounded-lg border border-bad-200 bg-bad-50 px-3 py-2 text-sm text-bad-700">{error}</p>
      )}

      {isLoading ? (
        <p className="text-sm text-ink-400">{t.common.loading}</p>
      ) : isError ? (
        <div className="rounded-xl border border-dashed border-ink-200 py-12 text-center">
          <p className="text-sm text-ink-500">{t.common.error}</p>
          <Button variant="secondary" size="sm" className="mt-3" onClick={invalidate}>{t.common.retry}</Button>
        </div>
      ) : !popups?.length ? (
        <div className="rounded-xl border border-dashed border-ink-200 py-16 text-center">
          <Megaphone className="mx-auto mb-3 size-8 text-ink-300" />
          <p className="text-sm text-ink-500">{t.popups.empty}</p>
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-2">
          {popups.map((p) => (
            <PopupCard key={p.id} popup={p} onChanged={invalidate} onError={fail} />
          ))}
        </div>
      )}
    </div>
  )
}

function PopupCard({ popup, onChanged, onError }: { popup: Popup; onChanged: () => void; onError: (e: unknown) => void }) {
  const t = useT()
  const fileRef = useRef<HTMLInputElement>(null)
  const [draft, setDraft] = useState({
    title_ar: popup.title_ar ?? '',
    title_en: popup.title_en ?? '',
    frequency: popup.frequency,
    starts_at: toLocalInput(popup.starts_at),
    ends_at: toLocalInput(popup.ends_at),
  })

  const save = useMutation({
    mutationFn: async (patch: Partial<Record<string, unknown>>) =>
      (await api.put<Popup>(`/merchant/popups/${popup.id}`, patch)).data,
    onSuccess: onChanged,
    onError,
  })
  const remove = useMutation({
    mutationFn: async () => api.delete(`/merchant/popups/${popup.id}`),
    onSuccess: onChanged,
    onError,
  })
  const upload = useMutation({
    mutationFn: async (file: File) => {
      const fd = new FormData()
      fd.append('image', file)
      return api.post(`/merchant/popups/${popup.id}/image`, fd, { headers: { 'Content-Type': 'multipart/form-data' } })
    },
    onSuccess: onChanged,
    onError,
  })

  const saveDetails = () =>
    save.mutate({
      title_ar: draft.title_ar || null,
      title_en: draft.title_en || null,
      frequency: draft.frequency,
      starts_at: draft.starts_at ? new Date(draft.starts_at).toISOString() : null,
      ends_at: draft.ends_at ? new Date(draft.ends_at).toISOString() : null,
    })

  const img = mediaUrl(popup.image)

  return (
    <div className="flex gap-4 rounded-2xl border border-ink-200 bg-white p-4">
      {/* Image: a phone-shaped preview, click to upload/replace. */}
      <button
        type="button"
        onClick={() => fileRef.current?.click()}
        className="relative aspect-[9/16] w-32 shrink-0 overflow-hidden rounded-xl border border-dashed border-ink-300 bg-ink-50"
        title={img ? t.popups.replaceImage : t.popups.upload}
      >
        {img ? (
          <img src={img} alt="" className="size-full object-cover" />
        ) : (
          <span className="flex size-full flex-col items-center justify-center gap-1 text-xs text-ink-400">
            <ImagePlus className="size-5" />
            {t.popups.upload}
          </span>
        )}
        {upload.isPending && (
          <span className="absolute inset-0 flex items-center justify-center bg-white/70 text-xs">{t.common.loading}</span>
        )}
      </button>
      <input
        ref={fileRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        className="hidden"
        onChange={(e) => {
          const f = e.target.files?.[0]
          if (f) upload.mutate(f)
          e.target.value = ''
        }}
      />

      <div className="min-w-0 flex-1 space-y-3">
        <div className="flex items-center justify-between gap-2">
          <label className="flex cursor-pointer items-center gap-2 text-sm">
            <span
              role="switch"
              aria-checked={popup.is_active}
              onClick={() => save.mutate({ is_active: !popup.is_active })}
              className={cn(
                'relative inline-block h-5 w-9 rounded-full transition-colors',
                popup.is_active ? 'bg-ink-900' : 'bg-ink-300',
              )}
            >
              <span
                className={cn(
                  'absolute top-0.5 size-4 rounded-full bg-white transition-all',
                  popup.is_active ? 'start-4' : 'start-0.5',
                )}
              />
            </span>
            <span className="text-ink-700">{popup.is_active ? t.popups.active : t.popups.inactive}</span>
          </label>
          <button
            type="button"
            onClick={() => { if (confirm(t.popups.confirmDelete)) remove.mutate() }}
            className="rounded-lg p-1.5 text-ink-400 hover:bg-bad-50 hover:text-bad-600"
            aria-label={t.common.delete}
          >
            <Trash2 className="size-4" />
          </button>
        </div>

        {!popup.image && <p className="text-xs text-amber-700">{t.popups.noImageHint}</p>}

        <Input label={t.popups.titleAr} value={draft.title_ar} maxLength={120}
          onChange={(e) => setDraft((d) => ({ ...d, title_ar: e.target.value }))} />
        <Input label={t.popups.titleEn} value={draft.title_en} maxLength={120} dir="ltr"
          onChange={(e) => setDraft((d) => ({ ...d, title_en: e.target.value }))} />

        <div>
          <label className="mb-1.5 block text-sm font-medium text-ink-700">{t.popups.frequency}</label>
          <div className="flex flex-wrap gap-2">
            {FREQUENCIES.map((f) => (
              <button
                key={f}
                type="button"
                onClick={() => setDraft((d) => ({ ...d, frequency: f }))}
                className={cn(
                  'rounded-full border px-3 py-1.5 text-xs font-medium',
                  draft.frequency === f ? 'border-ink-900 bg-ink-900 text-white' : 'border-ink-200 text-ink-600 hover:border-ink-400',
                )}
              >
                {t.popups.frequencies[f]}
              </button>
            ))}
          </div>
        </div>

        <div className="grid grid-cols-2 gap-2">
          <Input label={t.popups.startsAt} type="datetime-local" dir="ltr" value={draft.starts_at}
            onChange={(e) => setDraft((d) => ({ ...d, starts_at: e.target.value }))} />
          <Input label={t.popups.endsAt} type="datetime-local" dir="ltr" value={draft.ends_at}
            onChange={(e) => setDraft((d) => ({ ...d, ends_at: e.target.value }))} />
        </div>

        <Button size="sm" onClick={saveDetails} loading={save.isPending}>{t.common.save}</Button>
      </div>
    </div>
  )
}
