import { Plus, Trash2 } from 'lucide-react'
import type { BookingSettings, DeliveryTier } from '@/api/types'
import { useT } from '@/app/i18n'
import { Card, CardHeader } from '@/components/ui/Card'
import { Input } from '@/components/ui/Input'
import { cn } from '@/lib/cn'

/**
 * How delivery is priced: a flat fee, base + per-km, or distance tiers — plus
 * an optional radius. Mirrors DeliveryPricing on the server; the "example"
 * line below the editor is computed the same way so the merchant can sanity
 * check a figure before saving.
 */
const MODES = ['fixed', 'per_km', 'tiers'] as const
type Mode = (typeof MODES)[number]

export function DeliveryPricingCard({
  draft,
  set,
}: {
  draft: BookingSettings
  set: <K extends keyof BookingSettings>(key: K, value: BookingSettings[K]) => void
}) {
  const t = useT()
  const mode: Mode = MODES.includes(draft.delivery_pricing_mode) ? draft.delivery_pricing_mode : 'fixed'
  const tiers: DeliveryTier[] = Array.isArray(draft.delivery_tiers) ? draft.delivery_tiers : []
  const num = (v: unknown) => (v === '' || v == null ? 0 : Number(v))

  const setTier = (i: number, patch: Partial<DeliveryTier>) =>
    set('delivery_tiers', tiers.map((row, j) => (j === i ? { ...row, ...patch } : row)))

  const addTier = () => {
    const last = tiers[tiers.length - 1]
    set('delivery_tiers', [...tiers, { up_to_km: last ? num(last.up_to_km) + 5 : 5, fee: last ? num(last.fee) + 5 : num(draft.delivery_fee) || 10 }])
  }

  // The example a merchant sees: a customer 4 km away.
  const exampleKm = 4
  const example = (() => {
    if (mode === 'fixed') return num(draft.delivery_fee)
    if (mode === 'per_km') return num(draft.delivery_base_fee) + num(draft.delivery_fee_per_km) * exampleKm
    const tier = [...tiers].sort((a, b) => num(a.up_to_km) - num(b.up_to_km)).find((r) => exampleKm <= num(r.up_to_km))
    return tier ? num(tier.fee) : null
  })()

  return (
    <Card>
      <CardHeader title={t.settings.deliveryPricingTitle} />
      <div className="space-y-5 px-5 py-5">
        <p className="text-sm text-ink-500">{t.settings.deliveryPricingHint}</p>

        <div>
          <span className="mb-1.5 block text-[13px] font-medium text-ink-700">{t.settings.deliveryMode}</span>
          <div className="grid grid-cols-3 gap-2">
            {MODES.map((m) => (
              <button
                key={m}
                type="button"
                onClick={() => set('delivery_pricing_mode', m)}
                className={cn(
                  'rounded-lg border px-3 py-2.5 text-sm font-medium transition-colors',
                  mode === m
                    ? 'border-ink-900 bg-ink-900 text-white'
                    : 'border-ink-200 bg-white text-ink-700 hover:border-ink-400',
                )}
              >
                {t.settings.deliveryModes[m]}
              </button>
            ))}
          </div>
        </div>

        {mode === 'per_km' && (
          <div className="grid gap-4 sm:grid-cols-2">
            <Input label={t.settings.deliveryBaseFee} type="number" min={0} step="0.01"
              value={draft.delivery_base_fee}
              onChange={(e) => set('delivery_base_fee', Number(e.target.value))} />
            <Input label={t.settings.deliveryFeePerKm} type="number" min={0} step="0.01"
              value={draft.delivery_fee_per_km}
              onChange={(e) => set('delivery_fee_per_km', Number(e.target.value))} />
          </div>
        )}

        {mode === 'tiers' && (
          <div>
            <span className="mb-1.5 block text-[13px] font-medium text-ink-700">{t.settings.deliveryTiers}</span>
            <p className="mb-3 text-xs text-ink-500">{t.settings.deliveryTiersHint}</p>
            <div className="space-y-2">
              {tiers.map((row, i) => (
                <div key={i} className="flex items-end gap-2">
                  <Input label={i === 0 ? t.settings.tierUpToKm : undefined} type="number" min={0.1} step="0.1"
                    value={row.up_to_km}
                    onChange={(e) => setTier(i, { up_to_km: Number(e.target.value) })} />
                  <Input label={i === 0 ? t.settings.tierFee : undefined} type="number" min={0} step="0.01"
                    value={row.fee}
                    onChange={(e) => setTier(i, { fee: Number(e.target.value) })} />
                  <button
                    type="button"
                    onClick={() => set('delivery_tiers', tiers.filter((_, j) => j !== i))}
                    aria-label={t.common.delete}
                    className="mb-1 rounded-md p-2 text-ink-400 hover:bg-bad-50 hover:text-bad-600"
                  >
                    <Trash2 className="size-4" />
                  </button>
                </div>
              ))}
            </div>
            {tiers.length < 10 && (
              <button
                type="button"
                onClick={addTier}
                className="mt-3 inline-flex items-center gap-1.5 rounded-lg border border-ink-200 px-3 py-1.5 text-xs font-medium text-ink-700 hover:border-ink-400"
              >
                <Plus className="size-3.5" /> {t.settings.addTier}
              </button>
            )}
          </div>
        )}

        <div className="grid gap-4 sm:grid-cols-2">
          <Input label={t.settings.deliveryMaxDistance} hint={t.settings.deliveryMaxDistanceHint}
            type="number" min={0} max={500} step="0.5"
            value={draft.delivery_max_distance_km ?? 0}
            onChange={(e) => set('delivery_max_distance_km', Number(e.target.value))} />
          <Input label={t.settings.deliveryRoadFactor} hint={t.settings.deliveryRoadFactorHint}
            type="number" min={1} max={3} step="0.05"
            value={draft.delivery_road_factor}
            onChange={(e) => set('delivery_road_factor', Number(e.target.value))} />
        </div>

        {example != null && (
          <p className="rounded-lg bg-ink-50 px-3 py-2 text-xs text-ink-600">
            {t.settings.deliveryExample.replace('{km}', String(exampleKm)).replace('{fee}', example.toFixed(2))}
          </p>
        )}
      </div>
    </Card>
  )
}
