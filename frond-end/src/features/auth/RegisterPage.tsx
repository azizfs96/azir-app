import { useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { api, TOKEN_KEY, errorMessage } from '@/api/client'
import type { AuthUser } from '@/api/types'
import { useAuth } from '@/app/auth'
import { useI18n } from '@/app/i18n'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'

/**
 * MERCHANT SIGN-UP (spec §11 step 1) — the page the landing's "انضم الآن"
 * button lands on. One short form → POST /auth/merchant/register, which
 * creates the merchant + owner + store and returns a token. The new merchant
 * is `pending` until an admin approves them, so after sign-up they see the
 * pending screen rather than an empty dashboard.
 */
export function RegisterPage() {
  const { refresh } = useAuth()
  const { t, locale, setLocale } = useI18n()
  const navigate = useNavigate()

  const [form, setForm] = useState({
    business_name: '',
    business_type: 'restaurant',
    owner_name: '',
    email: '',
    phone: '',
    password: '',
  })
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  const set = (k: keyof typeof form) => (e: { target: { value: string } }) =>
    setForm((f) => ({ ...f, [k]: e.target.value }))

  async function onSubmit(event: FormEvent) {
    event.preventDefault()
    setBusy(true)
    setError(null)
    setFieldErrors({})
    try {
      const { data } = await api.post<{ token: string; user: AuthUser }>('/auth/merchant/register', {
        ...form,
        locale,
      })
      localStorage.setItem(TOKEN_KEY, data.token)
      await refresh()
      navigate('/', { replace: true })
    } catch (err) {
      // Laravel's 422 carries per-field messages; show them next to the field.
      const errors = (err as { response?: { data?: { errors?: Record<string, string[]> } } })
        .response?.data?.errors
      if (errors) {
        setFieldErrors(Object.fromEntries(Object.entries(errors).map(([k, v]) => [k, v[0]])))
      } else {
        setError(errorMessage(err, t.common.error))
      }
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex min-h-dvh items-center justify-center bg-ink-50 px-4 py-10">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <img src="/azir-logo.png" alt="Azir" className="mx-auto mb-3 h-16 w-auto" />
          <h1 className="text-lg font-semibold tracking-tight text-ink-900">{t.register.title}</h1>
          <p className="mt-1 text-sm text-ink-500">{t.register.subtitle}</p>
        </div>

        <form onSubmit={onSubmit} className="space-y-4 rounded-xl border border-ink-200 bg-white p-6">
          <Input
            label={t.register.businessName}
            name="business_name"
            required
            maxLength={120}
            value={form.business_name}
            onChange={set('business_name')}
            error={fieldErrors.business_name}
          />

          <div>
            <label className="mb-1.5 block text-sm font-medium text-ink-700">{t.register.businessType}</label>
            <div className="grid grid-cols-2 gap-2">
              {(['restaurant', 'beauty_wellness'] as const).map((type) => (
                <button
                  key={type}
                  type="button"
                  onClick={() => setForm((f) => ({ ...f, business_type: type }))}
                  className={
                    'rounded-lg border px-3 py-2.5 text-sm font-medium transition-colors ' +
                    (form.business_type === type
                      ? 'border-ink-900 bg-ink-900 text-white'
                      : 'border-ink-200 bg-white text-ink-700 hover:border-ink-400')
                  }
                >
                  {t.register.types[type]}
                </button>
              ))}
            </div>
          </div>

          <Input
            label={t.register.ownerName}
            name="owner_name"
            autoComplete="name"
            required
            maxLength={120}
            value={form.owner_name}
            onChange={set('owner_name')}
            error={fieldErrors.owner_name}
          />
          <Input
            label={t.register.phone}
            name="phone"
            type="tel"
            inputMode="tel"
            dir="ltr"
            autoComplete="tel"
            required
            placeholder="05XXXXXXXX"
            value={form.phone}
            onChange={set('phone')}
            error={fieldErrors.phone}
          />
          <Input
            label={t.auth.email}
            name="email"
            type="email"
            autoComplete="email"
            required
            value={form.email}
            onChange={set('email')}
            error={fieldErrors.email}
          />
          <Input
            label={t.auth.password}
            name="password"
            type="password"
            autoComplete="new-password"
            required
            minLength={8}
            hint={t.register.passwordHint}
            value={form.password}
            onChange={set('password')}
            error={fieldErrors.password ?? error}
          />

          <Button type="submit" className="w-full" loading={busy}>
            {busy ? t.register.submitting : t.register.submit}
          </Button>

          <p className="text-center text-xs text-ink-500">
            {t.register.haveAccount}{' '}
            <Link to="/login" className="font-medium text-ink-900 underline-offset-2 hover:underline">
              {t.auth.signIn}
            </Link>
          </p>
        </form>

        <button
          onClick={() => setLocale(locale === 'ar' ? 'en' : 'ar')}
          className="mx-auto mt-5 block text-xs text-ink-500 hover:text-ink-900"
        >
          {locale === 'ar' ? 'English' : 'العربية'}
        </button>
      </div>
    </div>
  )
}

/**
 * Shown instead of the dashboard while the merchant is not yet approved
 * (every /merchant/* call would 403 with MERCHANT_NOT_ACTIVE). Explains the
 * state instead of an empty board, and offers sign-out.
 */
export function PendingPage({ status }: { status: 'pending' | 'suspended' | 'rejected' }) {
  const { signOut, user } = useAuth()
  const { t } = useI18n()
  const copy = t.register.pending[status]

  return (
    <div className="flex min-h-dvh items-center justify-center bg-ink-50 px-4">
      <div className="w-full max-w-md rounded-xl border border-ink-200 bg-white p-8 text-center">
        <div className="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-ink-100 text-xl">
          {status === 'pending' ? '⏳' : '⛔'}
        </div>
        <h1 className="text-lg font-semibold text-ink-900">{copy.title}</h1>
        <p className="mt-2 text-sm leading-relaxed text-ink-500">{copy.body}</p>
        {user?.merchant?.display_name && (
          <p className="mt-4 text-xs text-ink-400">{user.merchant.display_name}</p>
        )}
        <Button variant="secondary" className="mt-6 w-full" onClick={() => void signOut()}>
          {t.nav.signOut}
        </Button>
      </div>
    </div>
  )
}
