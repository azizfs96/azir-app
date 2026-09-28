import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { MapPin, Pencil, Plus, Store, Trash2 } from 'lucide-react'
import { api, errorMessage } from '@/api/client'
import type { Branch } from '@/api/types'
import { useT } from '@/app/i18n'
import { Card, CardHeader } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { Modal } from '@/components/shared/Modal'
import { EmptyState } from '@/components/shared/EmptyState'
import { PageHeader } from '@/components/shared/PageHeader'
import {
  WeeklyHours, defaultWeek, scheduleFromWeek, validateWeek, weekFromSchedule,
  type DayHours,
} from '@/components/shared/WeeklyHours'
import { BranchForm, branchToForm, emptyBranchForm, type BranchFormValues } from './BranchForm'

/** Branch management (spec §16). One branch or many. */
export function BranchesPage() {
  const t = useT()
  const queryClient = useQueryClient()

  const [open, setOpen] = useState(false)
  // null = creating; a branch = editing that branch.
  const [editing, setEditing] = useState<Branch | null>(null)
  const [form, setForm] = useState<BranchFormValues>(emptyBranchForm())
  const [error, setError] = useState<string | null>(null)
  const [editingHours, setEditingHours] = useState<number | null>(null)
  const [hours, setHours] = useState<DayHours[]>(defaultWeek())

  const { data, isLoading } = useQuery({
    queryKey: ['branches'],
    queryFn: async () => (await api.get<{ data: Branch[] }>('/merchant/branches')).data.data,
  })

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ['branches'] })
    void queryClient.invalidateQueries({ queryKey: ['onboarding'] })
  }

  const payload = () => ({
    name_ar: form.name_ar,
    name_en: form.name_en || null,
    city: form.city || null,
    address_line: form.address_line || null,
    // The location the customer actually navigates to (spec §16).
    google_maps_url: form.google_maps_url || null,
    latitude: form.latitude,
    longitude: form.longitude,
  })

  const save = useMutation({
    mutationFn: async () => editing
      ? (await api.put(`/merchant/branches/${editing.id}`, payload())).data
      : (await api.post('/merchant/branches', payload())).data,
    onSuccess: () => {
      setOpen(false)
      setEditing(null)
      setForm(emptyBranchForm())
      invalidate()
    },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  function startCreate() {
    setEditing(null)
    setForm(emptyBranchForm())
    setError(null)
    setOpen(true)
  }

  function startEdit(branch: Branch) {
    setEditing(branch)
    setForm(branchToForm(branch))
    setError(null)
    setOpen(true)
  }

  const remove = useMutation({
    mutationFn: async (id: number) => (await api.delete(`/merchant/branches/${id}`)).data,
    onSuccess: invalidate,
    // The API refuses to delete the last branch — a store with none is
    // unbookable, and the failure would otherwise be silent.
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const [hoursErrors, setHoursErrors] = useState<string[]>([])

  const saveHours = useMutation({
    mutationFn: async (id: number) => (await api.put(`/merchant/branches/${id}/schedule`, {
      schedule: scheduleFromWeek(hours, { from: 'opens_at', to: 'closes_at', withBreaks: false }),
    })).data,
    onSuccess: () => { setEditingHours(null); setHoursErrors([]); invalidate() },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  function trySaveHours(id: number) {
    const problems = validateWeek(hours, t.weeklyHours.dayLabels, {
      breakOutside: t.weeklyHours.breakOutside,
      breakInverted: t.weeklyHours.breakInverted,
      overlap: t.weeklyHours.overlap,
    })

    setHoursErrors(problems)
    if (problems.length === 0) saveHours.mutate(id)
  }

  function openHours(branch: Branch) {
    setHours(weekFromSchedule(branch.schedule))
    setHoursErrors([])
    setEditingHours(branch.id)
  }

  const branches = data ?? []

  return (
    <>
      <PageHeader
        title={t.branchesPage.title}
        action={
          <Button onClick={startCreate}>
            <Plus className="size-4" />
            {t.branchesPage.add}
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
      ) : branches.length === 0 ? (
        <Card>
          <EmptyState
            icon={<Store className="size-8" />}
            title={t.branchesPage.empty}
            hint={t.branchesPage.emptyHint}
            action={<Button onClick={startCreate}>{t.branchesPage.add}</Button>}
          />
        </Card>
      ) : (
        <div className="space-y-5">
          {branches.map((branch) => (
            <Card key={branch.id}>
              <CardHeader
                title={branch.name}
                action={
                  <div className="flex items-center gap-2">
                    <Button size="sm" variant="secondary" onClick={() => startEdit(branch)}>
                      <Pencil className="size-3.5" />
                      {t.common.edit}
                    </Button>
                    <Button size="sm" variant="secondary" onClick={() => openHours(branch)}>
                      {t.branchesPage.hours}
                    </Button>
                    <button
                      onClick={() => confirm(t.branchesPage.deleteConfirm) && remove.mutate(branch.id)}
                      aria-label={t.common.delete}
                      className="rounded-md p-1.5 text-ink-400 hover:bg-bad-50 hover:text-bad-600"
                    >
                      <Trash2 className="size-4" />
                    </button>
                  </div>
                }
              />
              <div className="px-5 py-4 text-sm text-ink-500">
                {branch.city && <div>{branch.city}</div>}
                {branch.address && <div className="text-xs text-ink-400">{branch.address}</div>}

                {/* A branch with no map location is a booking the customer
                    cannot find, so say so plainly rather than showing nothing. */}
                <div className="mt-2">
                  {branch.google_maps_url ? (
                    <a
                      href={branch.google_maps_url}
                      target="_blank"
                      rel="noreferrer"
                      className="inline-flex items-center gap-1.5 text-xs font-medium text-ok-600 hover:underline"
                    >
                      <MapPin className="size-3.5" />
                      {t.branchesPage.openInMaps}
                    </a>
                  ) : (
                    <button
                      onClick={() => startEdit(branch)}
                      className="inline-flex items-center gap-1.5 text-xs font-medium text-warn-600 hover:underline"
                    >
                      <MapPin className="size-3.5" />
                      {t.branchesPage.noLocation}
                    </button>
                  )}
                </div>

                <div className="mt-2 text-xs text-ink-400">
                  {t.branchesPage.slotInterval}: {branch.slot_interval_minutes} {t.common.minutes}
                </div>
              </div>

              {editingHours === branch.id && (
                <div className="border-t border-ink-200">
                  <WeeklyHours
                    week={hours}
                    onChange={setHours}
                    saving={saveHours.isPending}
                    onSave={() => trySaveHours(branch.id)}
                    errors={hoursErrors}
                  />
                </div>
              )}
            </Card>
          ))}
        </div>
      )}

      <Modal
        open={open}
        onClose={() => setOpen(false)}
        title={editing ? t.branchesPage.editBranch : t.branchesPage.add}
        footer={
          <>
            <Button variant="secondary" onClick={() => setOpen(false)}>{t.common.cancel}</Button>
            <Button loading={save.isPending} onClick={() => save.mutate()}>{t.common.save}</Button>
          </>
        }
      >
        <BranchForm values={form} onChange={setForm} error={error} />
      </Modal>
    </>
  )
}
