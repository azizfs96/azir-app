import { useQueryClient } from '@tanstack/react-query'
import { NavLink, Outlet } from 'react-router-dom'
import { useStoreType } from '@/features/menu/useStoreType'
import {
  CalendarDays, LayoutDashboard, ListChecks, LogOut, QrCode,
  Scissors, Settings, Store, UserRound, Users, UtensilsCrossed,
  Megaphone, Bike, PackageSearch, Truck } from 'lucide-react'
import { api } from '@/api/client'
import { useAuth } from '@/app/auth'
import { useI18n } from '@/app/i18n'
import { cn } from '@/lib/cn'
import type { Locale } from '@/locales'

/**
 * The dashboard shell (spec §12).
 *
 * Sidebar navigation, mirrored automatically in Arabic by the `dir` attribute —
 * every spacing utility here is logical (ps-/pe-/border-s), so there is no
 * RTL-specific CSS anywhere in this file.
 */
export function AppShell() {
  const { t, locale, setLocale } = useI18n()
  const { user, signOut } = useAuth()
  const queryClient = useQueryClient()
  const { isRestaurant, isSupermarket } = useStoreType()

  /*
   * Switching language has to change BOTH sides.
   *
   * The interface strings come from the local dictionary, but service names,
   * branch names and status text come from the API — and SetLocale gives a
   * user's SAVED preference precedence over the Accept-Language header. So an
   * explicit toggle must persist the preference and then refetch, or the
   * merchant ends up with an English dashboard listing Arabic service names.
   */
  async function switchLocale(next: Locale) {
    setLocale(next)
    try {
      await api.patch('/auth/me/locale', { locale: next })
    } catch {
      // A failed save still leaves the interface switched; it will simply not
      // persist to the next session.
    }
    await queryClient.invalidateQueries()
  }

  // Each vertical has its own nav — a supermarket never sees bookings,
  // services or a kitchen board.
  const items = isSupermarket ? [
    { to: '/', icon: LayoutDashboard, label: t.grocery.nav.dashboard, end: true },
    { to: '/grocery-orders', icon: Truck, label: t.grocery.nav.orders },
    { to: '/catalog', icon: PackageSearch, label: t.grocery.nav.catalog },
    { to: '/drivers', icon: Bike, label: t.nav.drivers },
    { to: '/branches', icon: Store, label: t.nav.branches },
    { to: '/customers', icon: UserRound, label: t.nav.customers },
    { to: '/popups', icon: Megaphone, label: t.nav.popups },
    { to: '/qr', icon: QrCode, label: t.nav.qr },
    { to: '/settings', icon: Settings, label: t.nav.settings },
  ] : [
    { to: '/', icon: LayoutDashboard, label: t.nav.dashboard, end: true },
    // Restaurants take Orders; beauty stores take Bookings — same slot.
    isRestaurant
      ? { to: '/orders', icon: ListChecks, label: t.nav.orders }
      : { to: '/bookings', icon: ListChecks, label: t.nav.bookings },
    // Restaurants manage a Menu; beauty stores manage Services — same slot.
    isRestaurant
      ? { to: '/menu', icon: UtensilsCrossed, label: t.nav.menu }
      : { to: '/services', icon: Scissors, label: t.nav.services },
    { to: '/staff', icon: Users, label: t.nav.staff },
    // Delivery drivers only make sense for stores that take orders.
    ...(isRestaurant ? [{ to: '/drivers', icon: Bike, label: t.nav.drivers }] : []),
    { to: '/branches', icon: Store, label: t.nav.branches },
    { to: '/customers', icon: UserRound, label: t.nav.customers },
    { to: '/popups', icon: Megaphone, label: t.nav.popups },
    { to: '/qr', icon: QrCode, label: t.nav.qr },
    { to: '/settings', icon: Settings, label: t.nav.settings },
  ]

  return (
    <div className="flex min-h-dvh bg-ink-50">
      <aside className={cn('hidden w-60 shrink-0 flex-col border-e md:flex', isSupermarket ? 'border-fresh-800 bg-fresh-900 text-white' : 'border-ink-200 bg-white')}>
        <div className="flex items-center gap-2.5 px-5 py-5">
          <img src="/azir-logo.png" alt="Azir" className="size-8 rounded-lg" />
          <div className="leading-tight">
            <div className={cn('text-sm font-semibold', isSupermarket ? 'text-white' : 'text-ink-900')}>{t.brand.name}</div>
            <div className={cn('text-[11px]', isSupermarket ? 'text-fresh-400' : 'text-ink-400')}>{user?.merchant?.display_name}</div>
          </div>
        </div>

        <nav className="flex-1 space-y-0.5 px-3 py-2">
          {items.map(({ to, icon: Icon, label, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) => cn(
                'flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm transition-colors',
                isSupermarket
                  ? (isActive ? 'bg-white/15 font-medium text-white' : 'text-fresh-100/80 hover:bg-white/10 hover:text-white')
                  : (isActive ? 'bg-ink-100 font-medium text-ink-900' : 'text-ink-500 hover:bg-ink-50 hover:text-ink-900'),
              )}
            >
              <Icon className="size-4 shrink-0" />
              {label}
            </NavLink>
          ))}
        </nav>

        <div className={cn('space-y-0.5 border-t px-3 py-3', isSupermarket ? 'border-fresh-800 [&_button]:text-fresh-100/80 [&_button:hover]:bg-white/10 [&_button:hover]:text-white' : 'border-ink-200')}>
          <button
            onClick={() => void switchLocale(locale === 'ar' ? 'en' : 'ar')}
            className="flex w-full items-center gap-2.5 rounded-lg px-3 py-2 text-sm text-ink-500 hover:bg-ink-50 hover:text-ink-900"
          >
            <CalendarDays className="size-4" />
            {locale === 'ar' ? 'English' : 'العربية'}
          </button>
          <button
            onClick={() => void signOut()}
            className="flex w-full items-center gap-2.5 rounded-lg px-3 py-2 text-sm text-ink-500 hover:bg-ink-50 hover:text-ink-900"
          >
            <LogOut className="size-4" />
            {t.nav.signOut}
          </button>
        </div>
      </aside>

      <main className="flex-1 overflow-x-hidden px-5 py-6 md:px-8 md:py-8">
        <div className="mx-auto max-w-5xl">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
