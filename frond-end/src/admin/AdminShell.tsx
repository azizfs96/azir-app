import { NavLink, Outlet } from 'react-router-dom'
import { BarChart3, LogOut, Store } from 'lucide-react'
import { useAuth } from '@/app/auth'
import { useI18n } from '@/app/i18n'
import { cn } from '@/lib/cn'

/**
 * Admin shell (spec §39). A separate route tree with its own guard — an admin
 * is not a merchant and has no tenant.
 */
export function AdminShell() {
  const { t, locale, setLocale } = useI18n()
  const { signOut } = useAuth()

  const items = [
    { to: '/admin', icon: Store, label: t.admin.merchants, end: true },
    { to: '/admin/metrics', icon: BarChart3, label: t.admin.metrics },
  ]

  return (
    <div className="flex min-h-dvh bg-ink-50">
      <aside className="hidden w-56 shrink-0 flex-col border-e border-ink-200 bg-white md:flex">
        <div className="flex items-center gap-2.5 px-5 py-5">
          <div className="flex size-8 items-center justify-center rounded-lg bg-accent-600 text-sm font-semibold text-white">
            و
          </div>
          <div className="text-sm font-semibold text-ink-900">{t.admin.title}</div>
        </div>

        <nav className="flex-1 space-y-0.5 px-3 py-2">
          {items.map(({ to, icon: Icon, label, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) => cn(
                'flex items-center gap-2.5 rounded-lg px-3 py-2 text-sm transition-colors',
                isActive
                  ? 'bg-ink-100 font-medium text-ink-900'
                  : 'text-ink-500 hover:bg-ink-50 hover:text-ink-900',
              )}
            >
              <Icon className="size-4" />
              {label}
            </NavLink>
          ))}
        </nav>

        <div className="space-y-0.5 border-t border-ink-200 px-3 py-3">
          <button
            onClick={() => setLocale(locale === 'ar' ? 'en' : 'ar')}
            className="w-full rounded-lg px-3 py-2 text-start text-sm text-ink-500 hover:bg-ink-50"
          >
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
        <div className="mx-auto max-w-4xl">
          <Outlet />
        </div>
      </main>
    </div>
  )
}
