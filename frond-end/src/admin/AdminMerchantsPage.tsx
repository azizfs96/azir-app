import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { api, errorMessage } from '@/api/client'
import { useT } from '@/app/i18n'
import { Card } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Modal } from '@/components/shared/Modal'
import { EmptyState } from '@/components/shared/EmptyState'
import { PageHeader } from '@/components/shared/PageHeader'
import { cn } from '@/lib/cn'

type MerchantStatus = 'pending' | 'approved' | 'suspended' | 'rejected'

interface AdminMerchant {
  id: number
  display_name: string
  legal_name: string
  status: MerchantStatus
  contact_phone: string
  contact_email: string | null
  onboarding_complete: boolean
  bookings_count: number | null
  suspension_reason: string | null
  created_at: string | null
  owner: { name: string; email: string | null; phone: string | null } | null
  store: { token: string; name: string; is_published: boolean } | null
}

const statusStyles: Record<MerchantStatus, string> = {
  pending: 'bg-warn-50 text-warn-600',
  approved: 'bg-ok-50 text-ok-600',
  suspended: 'bg-bad-50 text-bad-600',
  rejected: 'bg-ink-100 text-ink-500',
}

/**
 * ============================================================================
 * THE APPROVAL QUEUE (spec §39)
 *
 * Every merchant registers as `pending`, and a pending merchant's store is
 * unreachable — their printed QR returns 404 for every customer. This screen is
 * what turns a signup into a live business.
 * ============================================================================
 */
export function AdminMerchantsPage() {
  const t = useT()
  const queryClient = useQueryClient()

  const [status, setStatus] = useState<MerchantStatus | 'all'>('pending')
  const [acting, setActing] = useState<{ merchant: AdminMerchant; action: 'reject' | 'suspend' } | null>(null)
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)

  const { data, isLoading } = useQuery({
    queryKey: ['admin-merchants', status],
    queryFn: async () => (await api.get<{ data: { data: AdminMerchant[] } }>(
      '/admin/merchants',
      { params: status === 'all' ? {} : { status } },
    )).data.data.data,
  })

  const act = useMutation({
    mutationFn: async ({ id, action, reason }: { id: number; action: string; reason?: string }) =>
      (await api.post(`/admin/merchants/${id}/${action}`, reason ? { reason } : {})).data,
    onSuccess: () => {
      setActing(null)
      setReason('')
      setError(null)
      void queryClient.invalidateQueries({ queryKey: ['admin-merchants'] })
      void queryClient.invalidateQueries({ queryKey: ['admin-metrics'] })
    },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const merchants = data ?? []

  const filters: Array<{ key: MerchantStatus | 'all'; label: string }> = [
    { key: 'pending', label: t.admin.pendingQueue },
    { key: 'approved', label: t.status.completed },
    { key: 'suspended', label: t.admin.suspend },
    { key: 'all', label: t.admin.allStatuses },
  ]

  return (
    <>
      <PageHeader title={t.admin.merchants} />

      <div className="mb-5 flex flex-wrap gap-2">
        {filters.map((filter) => (
          <button
            key={filter.key}
            onClick={() => setStatus(filter.key)}
            className={cn(
              'rounded-lg px-3 py-1.5 text-sm transition-colors',
              status === filter.key
                ? 'bg-ink-900 text-white'
                : 'border border-ink-200 bg-white text-ink-700 hover:bg-ink-50',
            )}
          >
            {filter.label}
          </button>
        ))}
      </div>

      {error && (
        <div className="mb-4 rounded-lg border border-bad-600/25 bg-bad-50 px-4 py-2.5 text-sm text-bad-600">
          {error}
        </div>
      )}

      <Card>
        {isLoading ? (
          <p className="px-5 py-8 text-sm text-ink-500">{t.common.loading}</p>
        ) : merchants.length === 0 ? (
          <EmptyState title={t.admin.noMerchants} />
        ) : (
          <ul className="divide-y divide-ink-200">
            {merchants.map((merchant) => (
              <li key={merchant.id} className="px-5 py-4">
                <div className="flex flex-wrap items-start justify-between gap-4">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-semibold text-ink-900">
                        {merchant.display_name}
                      </span>
                      <span className={cn(
                        'rounded-md px-2 py-0.5 text-xs font-medium',
                        statusStyles[merchant.status],
                      )}>
                        {merchant.status}
                      </span>
                    </div>

                    <div className="mt-1 text-xs text-ink-500">
                      {merchant.owner?.name}
                      {merchant.owner?.email && ` · ${merchant.owner.email}`}
                    </div>
                    <div className="mt-0.5 text-xs text-ink-400" dir="ltr">
                      {merchant.contact_phone}
                    </div>

                    {merchant.store && (
                      <div className="mt-1.5 flex items-center gap-2 text-xs text-ink-400">
                        <code className="rounded bg-ink-50 px-1.5 py-0.5 font-mono" dir="ltr">
                          {merchant.store.token}
                        </code>
                        {/* An admin needs to see whether the merchant actually
                            finished setup before approving them. */}
                        <span>{merchant.onboarding_complete ? '✓' : '—'}</span>
                      </div>
                    )}

                    {merchant.suspension_reason && (
                      <div className="mt-1.5 text-xs text-bad-600">
                        {merchant.suspension_reason}
                      </div>
                    )}
                  </div>

                  <div className="flex shrink-0 flex-wrap gap-2">
                    {merchant.status === 'pending' && (
                      <>
                        <Button
                          size="sm"
                          loading={act.isPending}
                          onClick={() => act.mutate({ id: merchant.id, action: 'approve' })}
                        >
                          {t.admin.approve}
                        </Button>
                        <Button
                          size="sm"
                          variant="danger"
                          onClick={() => { setActing({ merchant, action: 'reject' }); setError(null) }}
                        >
                          {t.admin.reject}
                        </Button>
                      </>
                    )}

                    {merchant.status === 'approved' && (
                      <Button
                        size="sm"
                        variant="danger"
                        onClick={() => { setActing({ merchant, action: 'suspend' }); setError(null) }}
                      >
                        {t.admin.suspend}
                      </Button>
                    )}

                    {merchant.status === 'suspended' && (
                      <Button
                        size="sm"
                        variant="secondary"
                        loading={act.isPending}
                        onClick={() => act.mutate({ id: merchant.id, action: 'reinstate' })}
                      >
                        {t.admin.reinstate}
                      </Button>
                    )}
                  </div>
                </div>
              </li>
            ))}
          </ul>
        )}
      </Card>

      {/* Reject and suspend both require a reason — it lands in the audit log
          and is the only record of why a business was cut off (spec §35). */}
      <Modal
        open={acting !== null}
        onClose={() => setActing(null)}
        title={acting?.action === 'reject' ? t.admin.reject : t.admin.suspend}
        footer={
          <>
            <Button variant="secondary" onClick={() => setActing(null)}>
              {t.common.cancel}
            </Button>
            <Button
              variant="danger"
              loading={act.isPending}
              onClick={() => {
                if (!reason.trim()) return setError(t.admin.reasonRequired)
                act.mutate({ id: acting!.merchant.id, action: acting!.action, reason })
              }}
            >
              {t.common.confirm}
            </Button>
          </>
        }
      >
        <p className="mb-4 text-sm text-ink-500">
          {acting?.action === 'suspend' ? t.admin.suspendConfirm : t.admin.approveConfirm}
        </p>
        <Input
          label={t.admin.reason}
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          error={error}
        />
      </Modal>
    </>
  )
}
