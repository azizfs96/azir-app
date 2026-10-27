import { useEffect } from 'react'
import { useQuery } from '@tanstack/react-query'
import L from 'leaflet'
import { MapContainer, Marker, Polyline, TileLayer, useMap } from 'react-leaflet'
import { api } from '@/api/client'
import type { OrderTracking } from '@/api/types'
import { useT } from '@/app/i18n'

/**
 * Live delivery tracking for one order: the driver's last position between the
 * branch and the customer, polled every 5 s while the order is out for
 * delivery. Small on purpose — it sits inside the order card.
 */

const pin = (color: string, glyph: string) =>
  L.divIcon({
    className: '',
    iconSize: [34, 34],
    iconAnchor: [17, 17],
    html: `<div style="width:34px;height:34px;border-radius:50%;background:#fff;border:2px solid ${color};display:flex;align-items:center;justify-content:center;box-shadow:0 2px 6px rgba(0,0,0,.25);font-size:16px">${glyph}</div>`,
  })

const ORIGIN = pin('#0A0A0B', '🏪')
const DEST = pin('#B42318', '📍')
const DRIVER = pin('#1D5FB8', '🛵')

type Point = [number, number]

function FitBounds({ points }: { points: Point[] }) {
  const map = useMap()
  useEffect(() => {
    if (points.length === 0) return
    if (points.length === 1) map.setView(points[0], 15)
    else map.fitBounds(L.latLngBounds(points), { padding: [28, 28] })
    // Fit on the set of pins, not on every driver tick — re-fitting each
    // poll would fight the merchant's own panning.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [map, points.length])
  return null
}

export function TrackingMap({ orderId, active }: { orderId: number; active: boolean }) {
  const t = useT()
  const { data } = useQuery({
    queryKey: ['order-tracking', orderId],
    queryFn: async () => (await api.get<OrderTracking>(`/merchant/orders/${orderId}/tracking`)).data,
    refetchInterval: active ? 5000 : false,
  })

  if (!data) return null

  const origin: Point | null =
    data.origin?.latitude != null && data.origin.longitude != null ? [data.origin.latitude, data.origin.longitude] : null
  const dest: Point | null =
    data.destination.latitude != null && data.destination.longitude != null
      ? [data.destination.latitude, data.destination.longitude]
      : null
  const driver: Point | null = data.driver_location
    ? [data.driver_location.latitude, data.driver_location.longitude]
    : null

  const points = [origin, dest, driver].filter((p): p is Point => p !== null)
  if (points.length === 0) return null

  const locatedAt = data.driver_location
    ? new Date(data.driver_location.located_at).toLocaleTimeString('ar', { hour: '2-digit', minute: '2-digit' })
    : null

  return (
    <div className="mt-3 overflow-hidden rounded-xl border border-ink-100">
      <div className="h-52">
        <MapContainer center={points[0]} zoom={14} scrollWheelZoom={false} className="h-full w-full" attributionControl={false}>
          <TileLayer url="https://tile.openstreetmap.org/{z}/{x}/{y}.png" />
          {origin && <Marker position={origin} icon={ORIGIN} />}
          {dest && <Marker position={dest} icon={DEST} />}
          {driver && <Marker position={driver} icon={DRIVER} />}
          {driver && dest && <Polyline positions={[driver, dest]} pathOptions={{ color: '#1D5FB8', weight: 3, dashArray: '6 8' }} />}
          {!driver && origin && dest && <Polyline positions={[origin, dest]} pathOptions={{ color: '#0A0A0B', weight: 2, opacity: 0.35, dashArray: '4 8' }} />}
          <FitBounds points={points} />
        </MapContainer>
      </div>
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 bg-ink-50 px-3 py-2 text-xs text-ink-600">
        {data.driver && <span className="font-semibold text-ink-900">{data.driver.name}</span>}
        {data.eta_minutes != null && <span>{t.orders.eta(data.eta_minutes)}</span>}
        {data.distance_km != null && <span>{t.orders.distanceKm(data.distance_km)}</span>}
        {locatedAt && (
          <span className={data.driver_location?.fresh ? 'text-ok-600' : 'text-warn-600'}>
            {data.driver_location?.fresh ? t.orders.locationLive : t.orders.locationStale} · {locatedAt}
          </span>
        )}
        {active && !data.driver_location && <span className="text-ink-400">{t.orders.waitingForLocation}</span>}
      </div>
    </div>
  )
}
