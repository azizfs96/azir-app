import axios, { AxiosError } from 'axios'

/**
 * The single HTTP client (ARCHITECTURE.md §7).
 *
 * Every API error carries a stable `error_code`; UI switches on that, never on
 * `message`, which is localized server-side.
 */
export const TOKEN_KEY = 'wasla.token'

// In dev, '/api/v1' is proxied to Laravel (vite.config). In production the
// dashboard and API are on different hosts (portal.azir.sa vs api.azir.sa), so
// VITE_API_BASE points at the real API origin.
export const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE ?? '/api/v1',
  headers: { Accept: 'application/json' },
})

/// Build a URL for a stored file (menu image, etc.). In dev '/storage' is
/// proxied to Laravel; in production VITE_MEDIA_BASE is the API origin
/// (https://api.azir.sa) that serves /storage.
export function mediaUrl(path: string | null | undefined): string | null {
  if (!path) return null
  if (path.startsWith('http')) return path
  const base = import.meta.env.VITE_MEDIA_BASE ?? ''
  return `${base}/storage/${path}`
}

api.interceptors.request.use((config) => {
  const token = localStorage.getItem(TOKEN_KEY)
  if (token) config.headers.Authorization = `Bearer ${token}`

  // The API localizes messages from this header (spec §33).
  config.headers['Accept-Language'] = localStorage.getItem('wasla.locale') ?? 'ar'
  return config
})

api.interceptors.response.use(
  (response) => response,
  (error: AxiosError<ApiError>) => {
    // An expired or revoked token should drop straight to the login screen
    // rather than leaving the dashboard in a half-broken state.
    if (error.response?.status === 401) {
      localStorage.removeItem(TOKEN_KEY)
      if (!window.location.pathname.startsWith('/login')) {
        window.location.href = '/login'
      }
    }
    return Promise.reject(error)
  },
)

export interface ApiError {
  message: string
  error_code?: string
  errors?: Record<string, string[]>
  blockers?: string[]
}

/** Pull a usable message out of any axios failure. */
export function errorMessage(error: unknown, fallback = 'Something went wrong'): string {
  const e = error as AxiosError<ApiError>
  return e?.response?.data?.message ?? fallback
}

export function errorCode(error: unknown): string | undefined {
  return (error as AxiosError<ApiError>)?.response?.data?.error_code
}
