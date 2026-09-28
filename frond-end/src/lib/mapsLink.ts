/**
 * Pull coordinates out of a Google Maps link a merchant pasted.
 *
 * Merchants do not type latitude and longitude — they open Maps, find their
 * shop, and hit Share. So the dashboard takes the link and extracts the
 * coordinates when it can.
 *
 * Handles the formats Google actually produces:
 *   .../maps/@24.7136,46.6753,17z
 *   .../maps/place/Name/@24.7136,46.6753,17z/data=...
 *   .../maps?q=24.7136,46.6753
 *   .../maps?ll=24.7136,46.6753
 *   geo:24.7136,46.6753
 *
 * Short links (maps.app.goo.gl/…) cannot be resolved without following the
 * redirect, which the browser cannot do cross-origin. That is fine: the URL
 * itself is what "View on map" needs, and coordinates are a bonus.
 */
export interface ParsedLocation {
  latitude: number | null
  longitude: number | null
}

const PATTERNS = [
  /@(-?\d+\.\d+),\s*(-?\d+\.\d+)/, //  /@lat,lng
  /[?&](?:q|ll|center|daddr)=(-?\d+\.\d+),\s*(-?\d+\.\d+)/, //  ?q=lat,lng
  /^geo:(-?\d+\.\d+),\s*(-?\d+\.\d+)/, //  geo:lat,lng
  /^\s*(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)\s*$/, //  bare "lat, lng" pasted
]

export function parseMapsLink(input: string): ParsedLocation {
  const value = input.trim()
  if (!value) return { latitude: null, longitude: null }

  for (const pattern of PATTERNS) {
    const match = value.match(pattern)
    if (!match) continue

    const latitude = Number(match[1])
    const longitude = Number(match[2])

    // Reject anything outside the real coordinate range — a zoom level or a
    // place id caught by a loose regex would otherwise become a location.
    if (
      Number.isFinite(latitude) && Number.isFinite(longitude) &&
      Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180
    ) {
      return { latitude, longitude }
    }
  }

  return { latitude: null, longitude: null }
}

/** Is this something we can hand to the customer app as a map link? */
export function isUsableMapsUrl(input: string): boolean {
  const value = input.trim()
  if (!value) return false

  try {
    const url = new URL(value)
    return url.protocol === 'https:' || url.protocol === 'http:'
  } catch {
    return false
  }
}
