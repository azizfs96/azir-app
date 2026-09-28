import { useState, type FormEvent } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/app/auth'
import { useI18n } from '@/app/i18n'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { errorMessage } from '@/api/client'

export function LoginPage() {
  const { signIn } = useAuth()
  const { t, locale, setLocale } = useI18n()
  const navigate = useNavigate()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function onSubmit(event: FormEvent) {
    event.preventDefault()
    setBusy(true)
    setError(null)
    try {
      await signIn(email, password)
      navigate('/', { replace: true })
    } catch (err) {
      setError(errorMessage(err, t.common.error))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex min-h-dvh items-center justify-center bg-ink-50 px-4">
      <div className="w-full max-w-sm">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-3 flex size-11 items-center justify-center rounded-xl bg-ink-900 text-lg font-semibold text-white">
            و
          </div>
          <h1 className="text-lg font-semibold tracking-tight text-ink-900">{t.auth.welcome}</h1>
          <p className="mt-1 text-sm text-ink-500">{t.auth.subtitle}</p>
        </div>

        <form onSubmit={onSubmit} className="space-y-4 rounded-xl border border-ink-200 bg-white p-6">
          <Input
            label={t.auth.email}
            name="email"
            type="email"
            autoComplete="username"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          <Input
            label={t.auth.password}
            name="password"
            type="password"
            autoComplete="current-password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            error={error}
          />
          <Button type="submit" className="w-full" loading={busy}>
            {busy ? t.auth.signingIn : t.auth.signIn}
          </Button>
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
