import { ar } from './ar'
import { en } from './en'

/**
 * Localization (spec §33).
 *
 *   "Do not hard-code text directly inside components. Use localization."
 *
 * Arabic is the DEFAULT and the design baseline; English is secondary. Both
 * dictionaries share one key shape, so a missing English string is a type
 * error rather than a blank label in production.
 */
/**
 * Same KEYS as the Arabic dictionary, but string values widened.
 *
 * `ar` is declared `as const` so its keys are exact — which also makes every
 * value a literal type. Without this mapped type, English would have to repeat
 * the Arabic strings verbatim to typecheck. This keeps missing/extra keys a
 * compile error while letting the translations differ.
 */
export type Translated<T> = {
  [K in keyof T]: T[K] extends string ? string : Translated<T[K]>
}

export type Dictionary = Translated<typeof ar>
export type Locale = 'ar' | 'en'

export const dictionaries: Record<Locale, Dictionary> = { ar, en }

export const LOCALE_KEY = 'wasla.locale'

export function storedLocale(): Locale {
  const stored = localStorage.getItem(LOCALE_KEY)
  return stored === 'en' ? 'en' : 'ar'
}

export function direction(locale: Locale) {
  return locale === 'ar' ? 'rtl' : 'ltr'
}
