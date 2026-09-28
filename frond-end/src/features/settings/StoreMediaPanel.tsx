import { useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ImageUp, Trash2 } from 'lucide-react'
import { api, errorMessage } from '@/api/client'
import { useT } from '@/app/i18n'
import { Card, CardHeader } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { cn } from '@/lib/cn'

interface StoreSettings {
  name_ar: string
  logo_url: string | null
  cover_url: string | null
  brand_color: string
}

/**
 * ============================================================================
 * STORE LOGO AND COVER
 *
 * These two images are the merchant's identity everywhere in the customer app:
 * the logo becomes the app-icon tile on the home screen and storefront, and the
 * cover is the photo behind the storefront header.
 *
 * Both previews are shown at the SHAPE the app will actually render them —
 * a rounded square for the logo, a wide banner for the cover — so a merchant
 * discovers a bad crop here rather than after printing their QR code.
 * ============================================================================
 */
export function StoreMediaPanel() {
  const t = useT()
  const queryClient = useQueryClient()
  const [error, setError] = useState<string | null>(null)

  const { data, isLoading } = useQuery({
    queryKey: ['store-settings'],
    queryFn: async () => (await api.get<{ store: StoreSettings }>('/merchant/settings/store')).data.store,
  })

  const upload = useMutation({
    mutationFn: async ({ type, file }: { type: 'logo' | 'cover'; file: File }) => {
      const body = new FormData()
      body.append('type', type)
      body.append('file', file)

      // Let the browser set the multipart boundary; overriding Content-Type
      // here is the classic way to break a file upload.
      return (await api.post('/merchant/settings/media', body)).data
    },
    onSuccess: () => {
      setError(null)
      void queryClient.invalidateQueries({ queryKey: ['store-settings'] })
    },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const remove = useMutation({
    mutationFn: async (type: 'logo' | 'cover') =>
      (await api.delete(`/merchant/settings/media/${type}`)).data,
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ['store-settings'] }),
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  if (isLoading || !data) {
    return <p className="text-sm text-ink-500">{t.common.loading}</p>
  }

  return (
    <Card>
      <CardHeader title={t.settings.brandImages} />

      <div className="space-y-6 px-5 py-5">
        {error && (
          <div className="rounded-lg border border-bad-600/25 bg-bad-50 px-4 py-2.5 text-sm text-bad-600">
            {error}
          </div>
        )}

        <MediaSlot
          type="logo"
          label={t.settings.logo}
          hint={t.settings.logoHint}
          url={data.logo_url}
          fallbackLetter={data.name_ar?.trim().charAt(0) || '؟'}
          brandColor={data.brand_color}
          shape="square"
          busy={upload.isPending}
          onPick={(file) => upload.mutate({ type: 'logo', file })}
          onRemove={() => remove.mutate('logo')}
        />

        <div className="h-px bg-ink-200" />

        <MediaSlot
          type="cover"
          label={t.settings.cover}
          hint={t.settings.coverHint}
          url={data.cover_url}
          brandColor={data.brand_color}
          shape="wide"
          busy={upload.isPending}
          onPick={(file) => upload.mutate({ type: 'cover', file })}
          onRemove={() => remove.mutate('cover')}
        />
      </div>
    </Card>
  )
}

function MediaSlot({
  label, hint, url, shape, brandColor, fallbackLetter, busy, onPick, onRemove,
}: {
  type: 'logo' | 'cover'
  label: string
  hint: string
  url: string | null
  shape: 'square' | 'wide'
  brandColor: string
  fallbackLetter?: string
  busy: boolean
  onPick: (file: File) => void
  onRemove: () => void
}) {
  const t = useT()
  const input = useRef<HTMLInputElement>(null)

  return (
    <div className="flex flex-wrap items-start gap-5">
      {/* Preview at the shape the customer app renders. */}
      <div
        className={cn(
          'shrink-0 overflow-hidden border border-ink-200 bg-ink-50',
          shape === 'square' ? 'size-20 rounded-[18px]' : 'h-20 w-40 rounded-lg',
        )}
      >
        {url ? (
          <img src={url} alt={label} className="size-full object-cover" />
        ) : (
          <div
            className="flex size-full items-center justify-center text-2xl font-semibold text-white"
            style={{ backgroundColor: brandColor }}
          >
            {shape === 'square' ? fallbackLetter : ''}
          </div>
        )}
      </div>

      <div className="min-w-0 flex-1">
        <div className="text-sm font-medium text-ink-900">{label}</div>
        <p className="mt-1 text-xs text-ink-500">{hint}</p>

        <div className="mt-3 flex flex-wrap gap-2">
          <Button size="sm" variant="secondary" loading={busy} onClick={() => input.current?.click()}>
            <ImageUp className="size-3.5" />
            {url ? t.settings.replaceImage : t.settings.uploadImage}
          </Button>

          {url && (
            <button
              onClick={onRemove}
              className="inline-flex items-center gap-1.5 rounded-lg px-2 py-1 text-xs text-ink-500 hover:bg-bad-50 hover:text-bad-600"
            >
              <Trash2 className="size-3.5" />
              {t.common.delete}
            </button>
          )}
        </div>

        <input
          ref={input}
          type="file"
          className="hidden"
          // Mirrors the server's allow-list; the server still re-checks the
          // actual bytes, because an accept attribute is a hint, not a control.
          accept="image/jpeg,image/png,image/webp"
          onChange={(e) => {
            const file = e.target.files?.[0]
            if (file) onPick(file)
            e.target.value = ''
          }}
        />
      </div>
    </div>
  )
}
