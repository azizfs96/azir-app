import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, Trash2, Users } from 'lucide-react'
import { api, errorMessage } from '@/api/client'
import type { Branch, StaffMember } from '@/api/types'
import { useT } from '@/app/i18n'
import { Card, CardHeader } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Modal } from '@/components/shared/Modal'
import { EmptyState } from '@/components/shared/EmptyState'
import { PageHeader } from '@/components/shared/PageHeader'
import { TimeOffModal } from './TimeOffModal'
import {
  WeeklyHours, defaultWeek, scheduleFromWeek, validateWeek, weekFromSchedule,
  type DayHours,
} from '@/components/shared/WeeklyHours'

/**
 * Staff management (spec §15).
 *
 * Staff are OPTIONAL throughout — a merchant with none still takes bookings
 * against the branch. The empty state says so rather than implying setup is
 * incomplete.
 */
export function StaffPage() {
  const t = useT()
  const queryClient = useQueryClient()

  const [open, setOpen] = useState(false)
  const [form, setForm] = useState({ name: '', title_ar: '', branch_id: '' })
  const [error, setError] = useState<string | null>(null)
  const [editingHours, setEditingHours] = useState<number | null>(null)
  const [timeOffFor, setTimeOffFor] = useState<StaffMember | null>(null)
  const [hours, setHours] = useState<DayHours[]>(defaultWeek())
  const [hoursErrors, setHoursErrors] = useState<string[]>([])

  const { data, isLoading } = useQuery({
    queryKey: ['staff'],
    queryFn: async () => (await api.get<{ data: StaffMember[] }>('/merchant/staff')).data.data,
  })

  const { data: branches } = useQuery({
    queryKey: ['branches'],
    queryFn: async () => (await api.get<{ data: Branch[] }>('/merchant/branches')).data.data,
  })

  const invalidate = () => void queryClient.invalidateQueries({ queryKey: ['staff'] })

  const create = useMutation({
    mutationFn: async () => (await api.post('/merchant/staff', {
      name: form.name,
      title_ar: form.title_ar || null,
      branch_id: form.branch_id ? Number(form.branch_id) : null,
    })).data,
    onSuccess: () => {
      setOpen(false)
      setForm({ name: '', title_ar: '', branch_id: '' })
      invalidate()
    },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const remove = useMutation({
    mutationFn: async (id: number) => (await api.delete(`/merchant/staff/${id}`)).data,
    onSuccess: invalidate,
  })

  const saveHours = useMutation({
    // Breaks and split shifts ride along now — the endpoint replaces the week
    // wholesale, so omitting them (as the old editor did) silently erased them
    // on every save.
    mutationFn: async (id: number) => (await api.put(`/merchant/staff/${id}/schedule`, {
      schedule: scheduleFromWeek(hours, { from: 'starts_at', to: 'ends_at', withBreaks: true }),
    })).data,
    onSuccess: () => { setEditingHours(null); setHoursErrors([]); invalidate() },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  function trySaveHours(id: number) {
    const labels = t.weeklyHours.dayLabels
    const problems = validateWeek(hours, labels, {
      breakOutside: t.weeklyHours.breakOutside,
      breakInverted: t.weeklyHours.breakInverted,
      overlap: t.weeklyHours.overlap,
    })

    setHoursErrors(problems)
    if (problems.length === 0) saveHours.mutate(id)
  }

  function openHours(member: StaffMember) {
    // ALL rows per day, breaks included — find() loaded only the first shift,
    // which is how second shifts were lost.
    setHours(weekFromSchedule(member.schedule))
    setHoursErrors([])
    setEditingHours(member.id)
  }

  const staff = data ?? []

  return (
    <>
      <PageHeader
        title={t.staffPage.title}
        action={
          <Button onClick={() => { setError(null); setOpen(true) }}>
            <Plus className="size-4" />
            {t.staffPage.add}
          </Button>
        }
      />

      {error && (
        <div className="mb-4 rounded-lg border border-bad-600/25 bg-bad-50 px-4 py-2.5 text-sm text-bad-600">
          {error}
        </div>
      )}

      {isLoading ? (
        <p className="text-sm text-ink-500">{t.common.loading}</p>
      ) : staff.length === 0 ? (
        <Card>
          <EmptyState
            icon={<Users className="size-8" />}
            title={t.staffPage.empty}
            hint={t.staffPage.emptyHint}
            action={<Button onClick={() => setOpen(true)}>{t.staffPage.add}</Button>}
          />
        </Card>
      ) : (
        <div className="space-y-5">
          {staff.map((member) => (
            <Card key={member.id}>
              <CardHeader
                title={
                  <span className="flex items-center gap-2">
                    {member.name}
                    {member.performs_all_services && (
                      // Spec §15: no assignments means they can do everything.
                      // Saying so prevents an empty list reading as "nothing".
                      <span className="rounded-md bg-ok-50 px-2 py-0.5 text-xs font-normal text-ok-600">
                        {t.staffPage.performsAll}
                      </span>
                    )}
                  </span>
                }
                action={
                  <div className="flex items-center gap-2">
                    <Button size="sm" variant="secondary" onClick={() => openHours(member)}>
                      {t.staffPage.hours}
                    </Button>
                    <Button size="sm" variant="secondary" onClick={() => setTimeOffFor(member)}>
                      {t.timeOff.button}
                    </Button>
                    <button
                      onClick={() => confirm(t.staffPage.deleteConfirm) && remove.mutate(member.id)}
                      aria-label={t.common.delete}
                      className="rounded-md p-1.5 text-ink-400 hover:bg-bad-50 hover:text-bad-600"
                    >
                      <Trash2 className="size-4" />
                    </button>
                  </div>
                }
              />
              <div className="px-5 py-3 text-sm text-ink-500">
                {member.title_ar || member.title_en || '—'}
                {!member.is_bookable && (
                  <span className="ms-2 text-xs text-warn-600">• {t.staffPage.bookable}: —</span>
                )}
              </div>

              {editingHours === member.id && (
                <div className="border-t border-ink-200">
                  <WeeklyHours
                    week={hours}
                    onChange={setHours}
                    saving={saveHours.isPending}
                    onSave={() => trySaveHours(member.id)}
                    withBreaks
                    errors={hoursErrors}
                  />
                </div>
              )}
            </Card>
          ))}
        </div>
      )}

      {timeOffFor && (
        <TimeOffModal
          staffId={timeOffFor.id}
          staffName={timeOffFor.name}
          onClose={() => setTimeOffFor(null)}
        />
      )}

      <Modal
        open={open}
        onClose={() => setOpen(false)}
        title={t.staffPage.add}
        footer={
          <>
            <Button variant="secondary" onClick={() => setOpen(false)}>{t.common.cancel}</Button>
            <Button loading={create.isPending} onClick={() => create.mutate()}>{t.common.save}</Button>
          </>
        }
      >
        <div className="space-y-4">
          <Input label={t.staffPage.name} value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })} />
          <Input label={t.staffPage.titleField} value={form.title_ar}
            onChange={(e) => setForm({ ...form, title_ar: e.target.value })} />

          <label className="block">
            <span className="mb-1.5 block text-[13px] font-medium text-ink-700">
              {t.branchesPage.title}
            </span>
            <select
              value={form.branch_id}
              onChange={(e) => setForm({ ...form, branch_id: e.target.value })}
              className="h-10 w-full rounded-lg border border-ink-200 bg-white px-3 text-sm"
            >
              <option value="">—</option>
              {(branches ?? []).map((branch) => (
                <option key={branch.id} value={branch.id}>{branch.name}</option>
              ))}
            </select>
          </label>
        </div>
      </Modal>
    </>
  )
}
