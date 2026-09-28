import { Navigate, Route, Routes } from 'react-router-dom'
import { useAuth } from '@/app/auth'
import { useT } from '@/app/i18n'
import { AppShell } from '@/app/AppShell'
import { LoginPage } from '@/features/auth/LoginPage'
import { DashboardPage } from '@/features/dashboard/DashboardPage'
import { BookingsPage } from '@/features/bookings/BookingsPage'
import { ServicesPage } from '@/features/services/ServicesPage'
import { MenuPage } from '@/features/menu/MenuPage'
import { OrdersPage } from '@/features/orders/OrdersPage'
import { QrPage } from '@/features/qr/QrPage'
import { SettingsPage } from '@/features/settings/SettingsPage'
import { StaffPage } from '@/features/staff/StaffPage'
import { BranchesPage } from '@/features/branches/BranchesPage'
import { CustomersPage } from '@/features/customers/CustomersPage'
import { AdminShell } from '@/admin/AdminShell'
import { AdminMerchantsPage } from '@/admin/AdminMerchantsPage'
import { AdminMetricsPage } from '@/admin/AdminMetricsPage'

/** Admins get their own tree; merchants must never reach it (spec §39). */
function AdminOnly({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth()
  const t = useT()

  if (loading) {
    return (
      <div className="flex min-h-dvh items-center justify-center text-sm text-ink-500">
        {t.common.loading}
      </div>
    )
  }

  if (!user) return <Navigate to="/login" replace />
  if (user.role !== 'admin') return <Navigate to="/" replace />

  return <>{children}</>
}

function Protected({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth()
  const t = useT()

  if (loading) {
    return (
      <div className="flex min-h-dvh items-center justify-center text-sm text-ink-500">
        {t.common.loading}
      </div>
    )
  }

  // Customers have their own app; only merchant users belong here (spec §34).
  if (!user || user.role === 'customer') return <Navigate to="/login" replace />

  // An admin has no tenant, so the merchant dashboard would query nothing.
  if (user.role === 'admin') return <Navigate to="/admin" replace />

  return <>{children}</>
}

export function AppRouter() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />

      <Route path="/admin" element={<AdminOnly><AdminShell /></AdminOnly>}>
        <Route index element={<AdminMerchantsPage />} />
        <Route path="metrics" element={<AdminMetricsPage />} />
      </Route>
      <Route path="/" element={<Protected><AppShell /></Protected>}>
        <Route index element={<DashboardPage />} />
        <Route path="bookings" element={<BookingsPage />} />
        <Route path="orders" element={<OrdersPage />} />
        <Route path="services" element={<ServicesPage />} />
        <Route path="menu" element={<MenuPage />} />
        <Route path="qr" element={<QrPage />} />
        <Route path="settings" element={<SettingsPage />} />
        <Route path="staff" element={<StaffPage />} />
        <Route path="branches" element={<BranchesPage />} />
        <Route path="customers" element={<CustomersPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
