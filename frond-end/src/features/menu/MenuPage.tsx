import { useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ImagePlus, Pencil, Plus, Star, Trash2, UtensilsCrossed } from 'lucide-react'
import { api, errorMessage, mediaUrl } from '@/api/client'
import type { MenuCategory, MenuItem } from '@/api/types'
import { useT } from '@/app/i18n'
import { Card, CardHeader } from '@/components/ui/Card'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Modal } from '@/components/shared/Modal'
import { EmptyState } from '@/components/shared/EmptyState'
import { PageHeader } from '@/components/shared/PageHeader'
import { cn } from '@/lib/cn'
import {
  OptionGroupsEditor, groupsAreValid,
  type GroupDraft,
} from './OptionGroupsEditor'

/**
 * ============================================================================
 * MENU MANAGEMENT (RestaurantEngine) — the merchant builds their menu here.
 *
 * Sections down the page, dishes within each. The item modal doubles as the
 * option-tree editor, so "بيج تيستي + الحجم + الإضافات" is one flow, not three
 * screens. Featured, sold-out and hidden are toggles the merchant flips live.
 * ============================================================================
 */
export function MenuPage() {
  const t = useT()
  const m = t.menuPage
  const queryClient = useQueryClient()

  const [catModal, setCatModal] = useState<MenuCategory | 'new' | null>(null)
  const [itemModal, setItemModal] = useState<MenuItem | 'new' | null>(null)
  const [error, setError] = useState<string | null>(null)

  const { data: categories, isLoading } = useQuery({
    queryKey: ['menu-categories'],
    queryFn: async () => (await api.get<{ data: MenuCategory[] }>('/merchant/menu/categories')).data.data,
  })

  const { data: items } = useQuery({
    queryKey: ['menu-items'],
    queryFn: async () => (await api.get<{ data: MenuItem[] }>('/merchant/menu/items')).data.data,
  })

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ['menu-categories'] })
    void queryClient.invalidateQueries({ queryKey: ['menu-items'] })
  }

  const removeItem = useMutation({
    mutationFn: async (id: number) => (await api.delete(`/merchant/menu/items/${id}`)).data,
    onSuccess: invalidate,
  })

  const removeCategory = useMutation({
    mutationFn: async (id: number) => (await api.delete(`/merchant/menu/categories/${id}`)).data,
    onSuccess: invalidate,
  })

  const toggleField = useMutation({
    mutationFn: async ({ id, field, value }: { id: number; field: string; value: boolean }) =>
      (await api.put(`/merchant/menu/items/${id}`, { [field]: value })).data,
    onSuccess: invalidate,
  })

  const allItems = items ?? []
  const cats = categories ?? []
  const itemsIn = (categoryId: number | null) =>
    allItems.filter((it) => it.category_id === categoryId)
      .sort((a, b) => a.sort_order - b.sort_order)

  const featured = allItems.filter((it) => it.is_featured)
  const uncategorised = itemsIn(null)
  const isEmpty = cats.length === 0 && allItems.length === 0

  return (
    <>
      <PageHeader
        title={m.title}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={() => { setError(null); setCatModal('new') }}>
              <Plus className="size-4" />
              {m.addCategory}
            </Button>
            <Button onClick={() => { setError(null); setItemModal('new') }}>
              <Plus className="size-4" />
              {m.addItem}
            </Button>
          </div>
        }
      />

      {isLoading ? (
        <p className="text-sm text-ink-500">{t.common.loading}</p>
      ) : isEmpty ? (
        <Card>
          <EmptyState
            icon={<UtensilsCrossed className="size-8" />}
            title={m.emptyTitle}
            hint={m.emptyHint}
            action={<Button onClick={() => setCatModal('new')}>{m.addCategory}</Button>}
          />
        </Card>
      ) : (
        <div className="space-y-5">
          {/* Featured strip — the "الأكثر طلباً" merchandising row. */}
          {featured.length > 0 && (
            <Card>
              <CardHeader
                title={
                  <span className="flex items-center gap-2">
                    <Star className="size-4 text-warn-600" />
                    {m.featured}
                  </span>
                }
              />
              <ul className="divide-y divide-ink-100">
                {featured.map((item) => (
                  <ItemRow
                    key={item.id} item={item} m={m} t={t}
                    onEdit={() => setItemModal(item)}
                    onDelete={() => confirm(m.deleteConfirm) && removeItem.mutate(item.id)}
                    onToggle={(field, value) => toggleField.mutate({ id: item.id, field, value })}
                  />
                ))}
              </ul>
            </Card>
          )}

          {cats.map((category) => (
            <Card key={category.id}>
              <CardHeader
                title={
                  <span className="flex items-center gap-2.5">
                    {mediaUrl(category.image) && (
                      <img
                        src={mediaUrl(category.image)!}
                        alt=""
                        className="size-7 rounded-md object-cover"
                      />
                    )}
                    {category.name}
                    {!category.is_active && (
                      <span className="rounded-md bg-ink-100 px-2 py-0.5 text-xs text-ink-500">
                        {m.hidden}
                      </span>
                    )}
                  </span>
                }
                action={
                  <div className="flex items-center gap-1">
                    <button
                      onClick={() => setCatModal(category)}
                      aria-label={m.editCategory}
                      className="rounded-md p-1.5 text-ink-400 hover:bg-ink-100 hover:text-ink-700"
                    >
                      <Pencil className="size-4" />
                    </button>
                    <button
                      onClick={() => confirm(m.deleteConfirm) && removeCategory.mutate(category.id)}
                      aria-label={t.common.delete}
                      className="rounded-md p-1.5 text-ink-400 hover:bg-bad-50 hover:text-bad-600"
                    >
                      <Trash2 className="size-4" />
                    </button>
                  </div>
                }
              />
              {itemsIn(category.id).length === 0 ? (
                <p className="px-5 py-4 text-sm text-ink-400">{m.noItems}</p>
              ) : (
                <ul className="divide-y divide-ink-100">
                  {itemsIn(category.id).map((item) => (
                    <ItemRow
                      key={item.id} item={item} m={m} t={t}
                      onEdit={() => setItemModal(item)}
                      onDelete={() => confirm(m.deleteConfirm) && removeItem.mutate(item.id)}
                      onToggle={(field, value) => toggleField.mutate({ id: item.id, field, value })}
                    />
                  ))}
                </ul>
              )}
            </Card>
          ))}

          {uncategorised.length > 0 && (
            <Card>
              <CardHeader title={m.uncategorised} />
              <ul className="divide-y divide-ink-100">
                {uncategorised.map((item) => (
                  <ItemRow
                    key={item.id} item={item} m={m} t={t}
                    onEdit={() => setItemModal(item)}
                    onDelete={() => confirm(m.deleteConfirm) && removeItem.mutate(item.id)}
                    onToggle={(field, value) => toggleField.mutate({ id: item.id, field, value })}
                  />
                ))}
              </ul>
            </Card>
          )}
        </div>
      )}

      {catModal !== null && (
        <CategoryModal
          category={catModal === 'new' ? null : catModal}
          onClose={() => setCatModal(null)}
          onSaved={invalidate}
        />
      )}

      {itemModal !== null && (
        <ItemModal
          item={itemModal === 'new' ? null : itemModal}
          categories={cats}
          onClose={() => setItemModal(null)}
          onSaved={invalidate}
        />
      )}

      {error && <p className="mt-3 text-sm text-bad-600">{error}</p>}
    </>
  )
}

// ---------------------------------------------------------------------------

function ItemRow({
  item, m, t, onEdit, onDelete, onToggle,
}: {
  item: MenuItem
  m: ReturnType<typeof useT>['menuPage']
  t: ReturnType<typeof useT>
  onEdit: () => void
  onDelete: () => void
  onToggle: (field: string, value: boolean) => void
}) {
  return (
    <li className={cn('flex items-center gap-3 px-5 py-3', !item.is_active && 'opacity-55')}>
      <div className="size-11 shrink-0 overflow-hidden rounded-lg bg-ink-100">
        {mediaUrl(item.image) ? (
          <img src={mediaUrl(item.image)!} alt="" className="size-full object-cover" />
        ) : (
          <div className="flex size-full items-center justify-center text-ink-300">
            <UtensilsCrossed className="size-5" />
          </div>
        )}
      </div>

      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <span className="truncate text-sm font-medium text-ink-900">{item.name}</span>
          {item.is_featured && <Star className="size-3.5 shrink-0 text-warn-600" />}
        </div>
        {item.description && (
          <div className="mt-0.5 truncate text-xs text-ink-500">{item.description}</div>
        )}
      </div>

      {/* Live sold-out toggle — the busiest control during service. */}
      <button
        onClick={() => onToggle('is_available', !item.is_available)}
        className={cn(
          'shrink-0 rounded-md px-2 py-1 text-xs font-medium',
          item.is_available ? 'bg-ok-50 text-ok-600' : 'bg-bad-50 text-bad-600',
        )}
      >
        {item.is_available ? m.available : m.soldOut}
      </button>

      <div className="shrink-0 text-sm font-medium tabular-nums text-ink-900">
        {item.price} {t.common.currency}
      </div>

      <button onClick={onEdit} aria-label={m.editItem}
        className="shrink-0 rounded-md p-1.5 text-ink-400 hover:bg-ink-100 hover:text-ink-700">
        <Pencil className="size-4" />
      </button>
      <button onClick={onDelete} aria-label={t.common.delete}
        className="shrink-0 rounded-md p-1.5 text-ink-400 hover:bg-bad-50 hover:text-bad-600">
        <Trash2 className="size-4" />
      </button>
    </li>
  )
}

// ---------------------------------------------------------------------------

function CategoryModal({
  category, onClose, onSaved,
}: {
  category: MenuCategory | null
  onClose: () => void
  onSaved: () => void
}) {
  const t = useT()
  const m = t.menuPage
  const [nameAr, setNameAr] = useState(category?.name_ar ?? '')
  const [nameEn, setNameEn] = useState(category?.name_en ?? '')
  const [error, setError] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  const save = useMutation({
    mutationFn: async () => {
      const body = { name_ar: nameAr, name_en: nameEn || null }
      const saved = category
        ? (await api.put(`/merchant/menu/categories/${category.id}`, body)).data
        : (await api.post('/merchant/menu/categories', body)).data

      const id = category?.id ?? saved.id
      const file = fileRef.current?.files?.[0]
      if (file) {
        const form = new FormData()
        form.append('image', file)
        await api.post(`/merchant/menu/categories/${id}/image`, form)
      }
      return saved
    },
    onSuccess: () => { onSaved(); onClose() },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  return (
    <Modal
      open onClose={onClose}
      title={category ? m.editCategory : m.addCategory}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>{t.common.cancel}</Button>
          <Button loading={save.isPending} onClick={() => save.mutate()}>{t.common.save}</Button>
        </>
      }
    >
      <div className="space-y-4">
        {error && <p className="text-sm text-bad-600">{error}</p>}
        <Input label={m.nameAr} value={nameAr} onChange={(e) => setNameAr(e.target.value)} />
        <Input label={m.nameEn} value={nameEn} onChange={(e) => setNameEn(e.target.value)} />
        <label className="block">
          <span className="mb-1.5 block text-[13px] font-medium text-ink-700">{m.image}</span>
          <input ref={fileRef} type="file" accept="image/*" className="text-sm text-ink-600" />
        </label>
      </div>
    </Modal>
  )
}

// ---------------------------------------------------------------------------

function ItemModal({
  item, categories, onClose, onSaved,
}: {
  item: MenuItem | null
  categories: MenuCategory[]
  onClose: () => void
  onSaved: () => void
}) {
  const t = useT()
  const m = t.menuPage
  const [form, setForm] = useState({
    name_ar: item?.name_ar ?? '',
    name_en: item?.name_en ?? '',
    description_ar: item?.description ?? '',
    price: item ? String(item.price) : '',
    calories: item?.calories != null ? String(item.calories) : '',
    category_id: item?.category_id != null ? String(item.category_id) : '',
    is_featured: item?.is_featured ?? false,
  })
  const [groups, setGroups] = useState<GroupDraft[]>(
    (item?.option_groups ?? []).map((g) => ({
      name_ar: g.name_ar,
      min_select: g.min_select,
      max_select: g.max_select,
      options: g.options.map((o) => ({ name_ar: o.name_ar, price_delta: String(o.price_delta) })),
    })),
  )
  const [error, setError] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  const save = useMutation({
    mutationFn: async () => {
      if (groups.length > 0 && !groupsAreValid(groups)) {
        throw new Error(m.minMaxError)
      }

      const body = {
        name_ar: form.name_ar,
        name_en: form.name_en || null,
        description_ar: form.description_ar || null,
        price: Number(form.price),
        calories: form.calories ? Number(form.calories) : null,
        menu_category_id: form.category_id ? Number(form.category_id) : null,
        is_featured: form.is_featured,
      }

      const saved = item
        ? (await api.put(`/merchant/menu/items/${item.id}`, body)).data
        : (await api.post('/merchant/menu/items', body)).data

      const id = item?.id ?? saved.id

      // Options ride a dedicated endpoint that replaces the whole tree.
      await api.put(`/merchant/menu/items/${id}/options`, {
        groups: groups.map((g) => ({
          name_ar: g.name_ar,
          min_select: g.min_select,
          max_select: g.max_select,
          options: g.options.map((o) => ({
            name_ar: o.name_ar,
            price_delta: Number(o.price_delta) || 0,
          })),
        })),
      })

      const file = fileRef.current?.files?.[0]
      if (file) {
        const fd = new FormData()
        fd.append('image', file)
        await api.post(`/merchant/menu/items/${id}/image`, fd)
      }
      return saved
    },
    onSuccess: () => { onSaved(); onClose() },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  return (
    <Modal
      open onClose={onClose}
      title={item ? m.editItem : m.addItem}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>{t.common.cancel}</Button>
          <Button loading={save.isPending} onClick={() => save.mutate()}>{t.common.save}</Button>
        </>
      }
    >
      <div className="space-y-4">
        {error && <p className="text-sm text-bad-600">{error}</p>}

        <div className="grid grid-cols-2 gap-3">
          <Input label={m.nameAr} value={form.name_ar}
            onChange={(e) => setForm({ ...form, name_ar: e.target.value })} />
          <Input label={m.nameEn} value={form.name_en}
            onChange={(e) => setForm({ ...form, name_en: e.target.value })} />
        </div>

        <Input label={m.descriptionAr} value={form.description_ar}
          onChange={(e) => setForm({ ...form, description_ar: e.target.value })} />

        <div className="grid grid-cols-2 gap-3">
          <Input label={m.price} type="number" min={0} value={form.price}
            onChange={(e) => setForm({ ...form, price: e.target.value })} />
          <Input label={m.calories} type="number" min={0} value={form.calories}
            onChange={(e) => setForm({ ...form, calories: e.target.value })} />
        </div>

        <label className="block">
          <span className="mb-1.5 block text-[13px] font-medium text-ink-700">{m.category}</span>
          <select
            value={form.category_id}
            onChange={(e) => setForm({ ...form, category_id: e.target.value })}
            className="h-10 w-full rounded-lg border border-ink-200 bg-white px-3 text-sm"
          >
            <option value="">{m.uncategorised}</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
        </label>

        <label className="flex cursor-pointer items-start gap-2.5 rounded-lg border border-ink-200 p-3">
          <input
            type="checkbox"
            checked={form.is_featured}
            onChange={(e) => setForm({ ...form, is_featured: e.target.checked })}
            className="mt-0.5 size-4 rounded border-ink-300"
          />
          <span>
            <span className="flex items-center gap-1.5 text-sm font-medium text-ink-900">
              <Star className="size-3.5 text-warn-600" />
              {m.featured}
            </span>
            <span className="text-xs text-ink-500">{m.featuredHint}</span>
          </span>
        </label>

        <label className="block">
          <span className="mb-1.5 flex items-center gap-1.5 text-[13px] font-medium text-ink-700">
            <ImagePlus className="size-3.5" />
            {item?.image ? m.changeImage : m.uploadImage}
          </span>
          <input ref={fileRef} type="file" accept="image/*" className="text-sm text-ink-600" />
        </label>

        <div className="border-t border-ink-200 pt-4">
          <OptionGroupsEditor groups={groups} onChange={setGroups} />
        </div>
      </div>
    </Modal>
  )
}
