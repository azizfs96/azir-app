import { useQuery } from '@tanstack/react-query'
import { api } from '@/api/client'

/**
 * The vertical this dashboard's store runs on.
 *
 * One cheap shared query (cached by TanStack) that the nav uses to show "Menu"
 * for a restaurant and "Services" for beauty — the engine is chosen server-side
 * from business_type, and the dashboard simply mirrors it.
 */
export function useStoreType() {
  const { data } = useQuery({
    queryKey: ['store-settings'],
    queryFn: async () =>
      (await api.get<{ store: { business_type?: string } }>('/merchant/settings/store')).data.store,
    staleTime: 5 * 60 * 1000,
  })

  return {
    businessType: data?.business_type ?? null,
    isRestaurant: data?.business_type === 'restaurant',
  }
}
