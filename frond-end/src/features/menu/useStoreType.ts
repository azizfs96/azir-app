import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'

export type BusinessType = 'beauty_wellness' | 'restaurant' | 'supermarket'

/**
 * Which vertical this merchant runs. The whole dashboard branches on this one
 * value (nav, home page, settings cards) — the API's `business_type` is the
 * single source of truth, cached for five minutes.
 */
export function useStoreType() {
  const { data } = useQuery({
    queryKey: ['store-settings'],
    queryFn: async () =>
      (await api.get<{ store: { business_type?: string } }>('/merchant/settings/store')).data.store,
    staleTime: 5 * 60 * 1000,
  })

  const businessType = (data?.business_type ?? null) as BusinessType | null

  return {
    businessType,
    isRestaurant: businessType === 'restaurant',
    isSupermarket: businessType === 'supermarket',
    /** Sells through the cart/order pipeline (restaurant or supermarket). */
    takesOrders: businessType === 'restaurant' || businessType === 'supermarket',
  }
}
