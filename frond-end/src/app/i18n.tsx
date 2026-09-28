import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { dictionaries, direction, LOCALE_KEY, storedLocale, type Dictionary, type Locale } from '@/locales'

interface I18nValue {
  locale: Locale
  dir: 'rtl' | 'ltr'
  t: Dictionary
  setLocale: (locale: Locale) => void
}

const I18nContext = createContext<I18nValue | null>(null)

/**
 * Locale + direction provider (spec §33).
 *
 * Setting `dir` on <html> is what mirrors the entire tree. Every layout uses
 * logical properties (ps-/pe-/ms-/me-/start-/end-), so nothing needs an
 * RTL-specific stylesheet.
 */
export function I18nProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(storedLocale)

  useEffect(() => {
    document.documentElement.lang = locale
    document.documentElement.dir = direction(locale)
  }, [locale])

  const setLocale = useCallback((next: Locale) => {
    localStorage.setItem(LOCALE_KEY, next)
    setLocaleState(next)
  }, [])

  const value = useMemo<I18nValue>(
    () => ({ locale, dir: direction(locale), t: dictionaries[locale], setLocale }),
    [locale, setLocale],
  )

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}

export function useI18n() {
  const context = useContext(I18nContext)
  if (!context) throw new Error('useI18n must be used inside <I18nProvider>')
  return context
}

/** Shorthand for the common case. */
export function useT() {
  return useI18n().t
}
