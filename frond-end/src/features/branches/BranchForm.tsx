import { useEffect, useState } from 'react'
import { MapPin } from 'lucide-react'
import { useT } from '@/app/i18n'
import { Input } from '@/components/ui/Input'
import { parseMapsLink, isUsableMapsUrl } from '@/lib/mapsLink'
import type { Branch } from '@/api/types'

export interface BranchFormValues {
  name_ar: string
  name_en: string
  city: string
  address_line: string
  google_maps_url: string
  latitude: number | null
  longitude: number | null
}

export function emptyBranchForm(): BranchFormValues {
  return {
    name_ar: '', name_en: '', city: '', address_line: '',
    google_maps_url: '', latitude: null, longitude: null,
  }
}

export function branchToForm(branch: Branch): BranchFormValues {
  return {
    name_ar: branch.name ?? '',
    name_en: '',
    city: branch.city ?? '',
    address_line: branch.address ?? '',
    google_maps_url: branch.google_maps_url ?? '',
    latitude: branch.latitude ?? null,
    longitude: branch.longitude ?? null,
  }
}

/**
 * Branch details including the actual map location (spec §16).
 *
 * A city name is not a location — a customer standing in Riyadh with a booking
 * needs to know WHICH building. So the merchant pastes a Google Maps link and
 * the coordinates are read out of it automatically; nobody types latitude by
 * hand.
 */
export function BranchForm({
  values, onChange, error,
}: {
  values: BranchFormValues
  onChange: (values: BranchFormValues) => void
  error?: string | null
}) {
  const t = useT()
  const [linkError, setLinkError] = useState<string | null>(null)

  // Re-read coordinates whenever the link changes.
  useEffect(() => {
    const link = values.google_maps_url.trim()

    if (!link) {
      setLinkError(null)
      if (values.latitude !== null || values.longitude !== null) {
        onChange({ ...values, latitude: null, longitude: null })
      }
      return
    }

    const { latitude, longitude } = parseMapsLink(link)

    // A short maps.app.goo.gl link carries no coordinates, and that is fine —
    // the URL alone is what the customer app needs for "View on map".
    setLinkError(isUsableMapsUrl(link) || latitude !== null ? null : t.branchesPage.mapsUrlInvalid)

    if (latitude !== values.latitude || longitude !== values.longitude) {
      onChange({ ...values, latitude, longitude })
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [values.google_maps_url])

  return (
    <div className="space-y-4">
      {error && <p className="text-sm text-bad-600">{error}</p>}

      <Input
        label={t.branchesPage.nameAr}
        value={values.name_ar}
        onChange={(e) => onChange({ ...values, name_ar: e.target.value })}
      />
      <Input
        label={t.branchesPage.nameEn}
        value={values.name_en}
        onChange={(e) => onChange({ ...values, name_en: e.target.value })}
      />

      <div className="grid grid-cols-2 gap-3">
        <Input
          label={t.branchesPage.city}
          value={values.city}
          onChange={(e) => onChange({ ...values, city: e.target.value })}
        />
        <Input
          label={t.branchesPage.address}
          value={values.address_line}
          onChange={(e) => onChange({ ...values, address_line: e.target.value })}
        />
      </div>

      <div>
        <Input
          label={t.branchesPage.mapsUrl}
          placeholder="https://maps.app.goo.gl/…"
          dir="ltr"
          value={values.google_maps_url}
          onChange={(e) => onChange({ ...values, google_maps_url: e.target.value })}
          hint={t.branchesPage.mapsUrlHint}
          error={linkError}
        />

        {/* Confirm what was understood, so the merchant is not guessing. */}
        {values.latitude !== null && values.longitude !== null && (
          <div className="mt-2 flex items-center gap-2 rounded-lg bg-ok-50 px-3 py-2 text-xs text-ok-600">
            <MapPin className="size-3.5 shrink-0" />
            <span>{t.branchesPage.coordinatesFound}</span>
            <code className="ms-auto font-mono" dir="ltr">
              {values.latitude.toFixed(5)}, {values.longitude.toFixed(5)}
            </code>
          </div>
        )}
      </div>
    </div>
  )
}
