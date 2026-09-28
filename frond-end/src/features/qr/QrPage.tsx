import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Copy, Download, RefreshCw } from 'lucide-react'
import { api } from '@/api/client'
import type { QrData } from '@/api/types'
import { useT } from '@/app/i18n'
import { Card } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { PageHeader } from '@/components/shared/PageHeader'

/**
 * The merchant's QR code (spec §24, §25).
 *
 * This page IS the product for a merchant: they print this, stick it on the
 * window, and customers arrive.
 */
export function QrPage() {
  const t = useT()
  const queryClient = useQueryClient()
  const [copied, setCopied] = useState(false)

  const { data, isLoading } = useQuery({
    queryKey: ['qr'],
    queryFn: async () => (await api.get<QrData>('/merchant/qr')).data,
  })

  const regenerate = useMutation({
    mutationFn: async () => (await api.post('/merchant/qr/regenerate')).data,
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: ['qr'] }),
  })

  if (isLoading || !data) return <p className="text-sm text-ink-500">{t.common.loading}</p>

  const stats = [
    { label: t.qr.scans, value: data.analytics.total_scans },
    { label: t.qr.uniqueCustomers, value: data.analytics.unique_customers },
    { label: t.qr.bookingsFromQr, value: data.analytics.bookings_from_qr },
  ]

  async function copyLink() {
    await navigator.clipboard.writeText(data!.deep_link)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <>
      <PageHeader title={t.qr.title} subtitle={t.qr.subtitle} />

      <div className="grid gap-5 lg:grid-cols-2">
        <Card className="flex flex-col items-center px-6 py-8">
          {data.image_url && (
            <img
              src={data.image_url}
              alt={t.qr.title}
              className="size-56 rounded-lg border border-ink-200"
            />
          )}

          {/* The token is shown in full: it doubles as the "enter store code"
              fallback when iOS deferred deep linking misses (§8.3). */}
          <div className="mt-4 text-center">
            <div className="font-mono text-lg font-semibold tracking-widest text-ink-900" dir="ltr">
              {data.token}
            </div>
          </div>

          <div className="mt-5 flex flex-wrap justify-center gap-2">
            {data.image_url && (
              <a href={data.image_url} download={`wasla-${data.token}.png`}>
                <Button variant="secondary" size="sm">
                  <Download className="size-4" />
                  {t.qr.download}
                </Button>
              </a>
            )}
            <a href={data.download_svg_url}>
              <Button variant="secondary" size="sm">
                <Download className="size-4" />
                {t.qr.downloadSvg}
              </Button>
            </a>
          </div>
        </Card>

        <div className="space-y-5">
          <Card className="px-5 py-4">
            <div className="text-xs text-ink-500">{t.qr.link}</div>
            <div className="mt-2 flex items-center gap-2">
              <code className="min-w-0 flex-1 truncate rounded-lg bg-ink-50 px-3 py-2 text-xs text-ink-700" dir="ltr">
                {data.deep_link}
              </code>
              <Button variant="secondary" size="sm" onClick={copyLink}>
                <Copy className="size-3.5" />
                {copied ? t.qr.copied : ''}
              </Button>
            </div>
          </Card>

          <div className="grid grid-cols-3 gap-px overflow-hidden rounded-[10px] border border-ink-200 bg-ink-200">
            {stats.map((stat) => (
              <div key={stat.label} className="bg-white px-4 py-4">
                <div className="text-xl font-semibold tabular-nums text-ink-900">{stat.value}</div>
                <div className="mt-0.5 text-xs text-ink-500">{stat.label}</div>
              </div>
            ))}
          </div>

          <Card className="px-5 py-4">
            {/* Destructive: every printed code stops working, so it warns first. */}
            <Button
              variant="danger"
              size="sm"
              loading={regenerate.isPending}
              onClick={() => confirm(t.qr.regenerateWarning) && regenerate.mutate()}
            >
              <RefreshCw className="size-3.5" />
              {t.qr.regenerate}
            </Button>
          </Card>
        </div>
      </div>
    </>
  )
}
