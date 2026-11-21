import { useMemo, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ImagePlus, Pencil, Plus, Search, ShoppingBasket, Star, Trash2 } from 'lucide-react'
import { api, errorMessage, mediaUrl, type ApiError } from '@/api/client'
import type { MenuCategory, MenuItem } from '@/api/types'
import { useT } from '@/app/i18n'
import { Button } from '@/components/ui/Button'
import { Input } from '@/components/ui/Input'
import { Modal } from '@/components/shared/Modal'
import { PageHeader } from '@/components/shared/PageHeader'
import { cn } from '@/lib/cn'
import { categoryGlyph } from './categoryGlyph'

/**
 * The supermarket catalogue: a product GRID (not a menu list) with the fields
 * groceries actually have — unit, compare-at price, stock — and the category
 * strip the customer app mirrors as round chips. Same /merchant/menu API as
 * the restaurant; the engine makes the extra fields meaningful.
 */
type ProductForm = {
  name_ar: string; name_en: string; description_ar: string; category_id: string
  price: string; compare_at_price: string; unit: string; stock_quantity: string; is_featured: boolean
}
const EMPTY_PRODUCT: ProductForm = {
  name_ar: '', name_en: '', description_ar: '', category_id: '', price: '', compare_at_price: '', unit: '', stock_quantity: '', is_featured: false,
}

export function CatalogPage() {
  const t = useT()
  const c = t.grocery.catalog
  const queryClient = useQueryClient()

  const [filter, setFilter] = useState<'all' | number>('all')
  const [search, setSearch] = useState('')
  const [editing, setEditing] = useState<MenuItem | null | 'new'>(null)
  const [editingCategory, setEditingCategory] = useState<MenuCategory | null | 'new'>(null)
  const [error, setError] = useState<string | null>(null)

  const { data: categories } = useQuery({
    queryKey: ['menu-categories'],
    queryFn: async () => (await api.get<{ data: MenuCategory[] }>('/merchant/menu/categories')).data.data,
  })
  const { data: items, isLoading } = useQuery({
    queryKey: ['menu-items'],
    queryFn: async () => (await api.get<{ data: MenuItem[] }>('/merchant/menu/items')).data.data,
  })

  const invalidate = () => {
    void queryClient.invalidateQueries({ queryKey: ['menu-items'] })
    void queryClient.invalidateQueries({ queryKey: ['menu-categories'] })
    void queryClient.invalidateQueries({ queryKey: ['grocery-dashboard'] })
  }

  const toggle = useMutation({
    mutationFn: async (vars: { id: number; field: 'is_available' | 'is_featured'; value: boolean }) =>
      (await api.put(`/merchant/menu/items/${vars.id}`, { [vars.field]: vars.value })).data,
    onSuccess: invalidate,
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })
  const remove = useMutation({
    mutationFn: async (id: number) => (await api.delete(`/merchant/menu/items/${id}`)).data,
    onSuccess: invalidate,
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })
  const removeCategory = useMutation({
    mutationFn: async (id: number) => (await api.delete(`/merchant/menu/categories/${id}`)).data,
    onSuccess: () => { setFilter('all'); invalidate() },
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  const sortedCategories = useMemo(
    () => [...(categories ?? [])].sort((a, b) => a.sort_order - b.sort_order),
    [categories],
  )
  const visible = useMemo(() => {
    const q = search.trim().toLowerCase()
    return (items ?? [])
      .filter((i) => filter === 'all' || i.category_id === filter)
      .filter((i) => !q || i.name_ar.toLowerCase().includes(q) || (i.name_en ?? '').toLowerCase().includes(q))
      .sort((a, b) => a.sort_order - b.sort_order || a.id - b.id)
  }, [items, filter, search])

  return (
    <>
      <PageHeader
        title={c.title}
        subtitle={c.subtitle}
        action={
          <div className="flex gap-2">
            <Button variant="secondary" onClick={() => setEditingCategory('new')}>{c.addCategory}</Button>
            <Button className="bg-fresh-700 hover:bg-fresh-800" onClick={() => setEditing('new')}>
              <Plus className="size-4" /> {c.add}
            </Button>
          </div>
        }
      />

      {error && (
        <div className="mb-4 rounded-lg border border-bad-600/25 bg-bad-50 px-4 py-2.5 text-sm text-bad-600">{error}</div>
      )}

      {/* Category strip — the same round chips the customer sees. */}
      <div className="mb-4 flex gap-3 overflow-x-auto pb-2">
        <CategoryChip label={c.all} active={filter === 'all'} onClick={() => setFilter('all')} count={items?.length ?? 0} />
        {sortedCategories.map((cat) => (
          <CategoryChip
            key={cat.id}
            label={cat.name_ar}
            image={cat.image}
            glyph={categoryGlyph(cat.name_ar + ' ' + (cat.name_en ?? ''))}
            active={filter === cat.id}
            muted={!cat.is_active}
            count={(items ?? []).filter((i) => i.category_id === cat.id).length}
            onClick={() => setFilter(cat.id)}
            onEdit={() => setEditingCategory(cat)}
            onDelete={() => confirm(c.deleteCategoryConfirm) && removeCategory.mutate(cat.id)}
          />
        ))}
      </div>

      <div className="relative mb-4">
        <Search className="pointer-events-none absolute start-3 top-1/2 size-4 -translate-y-1/2 text-ink-400" />
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder={c.search}
          className="h-10 w-full rounded-lg border border-ink-200 bg-white ps-9 pe-3 text-sm outline-none focus:border-fresh-600"
        />
      </div>

      {isLoading ? (
        <p className="text-sm text-ink-500">{t.common.loading}</p>
      ) : (items ?? []).length === 0 ? (
        <div className="rounded-2xl border border-dashed border-ink-200 py-16 text-center">
          <ShoppingBasket className="mx-auto mb-3 size-8 text-ink-300" />
          <p className="text-sm font-medium text-ink-900">{c.empty}</p>
          <p className="mt-1 text-xs text-ink-500">{c.emptyHint}</p>
          <Button className="mt-4 bg-fresh-700 hover:bg-fresh-800" onClick={() => setEditing('new')}>{c.add}</Button>
        </div>
      ) : visible.length === 0 ? (
        <p className="py-10 text-center text-sm text-ink-500">{c.noResults}</p>
      ) : (
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          {visible.map((item) => (
            <ProductCard
              key={item.id}
              item={item}
              busy={toggle.isPending}
              onToggleAvailable={() => toggle.mutate({ id: item.id, field: 'is_available', value: !item.is_available })}
              onToggleFeatured={() => toggle.mutate({ id: item.id, field: 'is_featured', value: !item.is_featured })}
              glyph={categoryGlyph(sortedCategories.find((cat) => cat.id === item.category_id)?.name_ar ?? '')}
              onEdit={() => setEditing(item)}
              onDelete={() => confirm(c.deleteConfirm) && remove.mutate(item.id)}
            />
          ))}
        </div>
      )}

      {editing !== null && (
        <ProductModal
          item={editing === 'new' ? null : editing}
          categories={sortedCategories}
          defaultCategory={filter === 'all' ? '' : String(filter)}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); invalidate() }}
        />
      )}
      {editingCategory !== null && (
        <CategoryModal
          category={editingCategory === 'new' ? null : editingCategory}
          onClose={() => setEditingCategory(null)}
          onSaved={() => { setEditingCategory(null); invalidate() }}
        />
      )}
    </>
  )
}

function CategoryChip({
  label, image, glyph, active, muted, count, onClick, onEdit, onDelete,
}: {
  label: string; image?: string | null; glyph?: string; active: boolean; muted?: boolean; count: number
  onClick: () => void; onEdit?: () => void; onDelete?: () => void
}) {
  const t = useT()
  return (
    <div className="group relative shrink-0">
      <button
        onClick={onClick}
        className={cn('flex w-20 flex-col items-center gap-1.5 text-center', muted && 'opacity-55')}
      >
        <span className={cn(
          'flex size-14 items-center justify-center overflow-hidden rounded-full border-2 bg-fresh-50 transition-colors',
          active ? 'border-fresh-600' : 'border-transparent',
        )}>
          {image
            ? <img src={mediaUrl(image) ?? undefined} alt="" className="size-full object-cover" />
            : <span className="text-2xl leading-none" aria-hidden>{glyph ?? '🛒'}</span>}
        </span>
        <span className={cn('line-clamp-2 text-[11px] leading-tight', active ? 'font-semibold text-ink-900' : 'text-ink-600')}>
          {label}
        </span>
        <span className="text-[10px] text-ink-400">{count}</span>
      </button>
      {onEdit && (
        <div className="absolute -top-1 end-0 hidden gap-0.5 group-hover:flex">
          <button onClick={onEdit} aria-label={t.common.edit} className="rounded-md bg-white p-1 text-ink-500 shadow hover:text-ink-900"><Pencil className="size-3" /></button>
          <button onClick={onDelete} aria-label={t.common.delete} className="rounded-md bg-white p-1 text-ink-500 shadow hover:text-bad-600"><Trash2 className="size-3" /></button>
        </div>
      )}
    </div>
  )
}

function ProductCard({
  item, busy, glyph, onToggleAvailable, onToggleFeatured, onEdit, onDelete,
}: {
  item: MenuItem; busy: boolean; glyph: string
  onToggleAvailable: () => void; onToggleFeatured: () => void; onEdit: () => void; onDelete: () => void
}) {
  const t = useT()
  const c = t.grocery.catalog
  const soldOut = !item.is_available || !item.in_stock
  const low = item.stock_quantity != null && item.stock_quantity > 0 && item.stock_quantity <= 5

  return (
    <div className={cn('flex flex-col overflow-hidden rounded-2xl border border-ink-200 bg-white', !item.is_active && 'opacity-55')}>
      <div className="relative aspect-square bg-fresh-50">
        {item.image
          ? <img src={mediaUrl(item.image) ?? undefined} alt="" className={cn('size-full object-cover', soldOut && 'grayscale')} />
          : <span className="absolute inset-0 flex items-center justify-center text-5xl" aria-hidden>{glyph}</span>}
        {item.discount_percent != null && (
          <span className="absolute start-2 top-2 rounded-md bg-fresh-600 px-1.5 py-0.5 text-[11px] font-bold text-white">
            {c.discount(item.discount_percent)}
          </span>
        )}
        <button
          onClick={onToggleFeatured}
          disabled={busy}
          aria-label={c.bestSeller}
          className={cn('absolute end-2 top-2 rounded-full bg-white/90 p-1.5 shadow', item.is_featured ? 'text-warn-600' : 'text-ink-300')}
        >
          <Star className={cn('size-4', item.is_featured && 'fill-current')} />
        </button>
        {soldOut && (
          <span className="absolute inset-x-0 bottom-0 bg-ink-900/80 py-1 text-center text-[11px] font-semibold text-white">
            {c.outOfStock}
          </span>
        )}
      </div>

      <div className="flex flex-1 flex-col p-3">
        <div className="line-clamp-2 text-sm font-semibold text-ink-900">{item.name_ar}</div>
        <div className="mt-0.5 text-xs text-ink-500">{item.unit ?? '—'}</div>
        <div className="mt-2 flex items-baseline gap-2">
          <span className="font-bold tabular-nums text-fresh-800">{item.price} {t.common.currency}</span>
          {item.compare_at_price != null && (
            <span className="text-xs tabular-nums text-ink-400 line-through">{item.compare_at_price}</span>
          )}
        </div>
        <div className="mt-1 text-[11px]">
          {item.stock_quantity == null
            ? <span className="text-ink-400">{c.untracked}</span>
            : <span className={cn(item.stock_quantity === 0 ? 'text-bad-600' : low ? 'text-warn-600' : 'text-ink-500')}>
                {c.inStock(item.stock_quantity)}{low && ` · ${c.low}`}
              </span>}
        </div>

        <div className="mt-3 flex items-center gap-1 border-t border-ink-100 pt-2">
          <button
            onClick={onToggleAvailable}
            disabled={busy}
            className={cn(
              'flex-1 rounded-md px-2 py-1 text-[11px] font-semibold',
              item.is_available ? 'bg-ok-50 text-ok-600' : 'bg-bad-50 text-bad-600',
            )}
          >
            {item.is_available ? c.available : c.unavailable}
          </button>
          <button onClick={onEdit} aria-label={t.common.edit} className="rounded-md p-1.5 text-ink-400 hover:bg-ink-100 hover:text-ink-900"><Pencil className="size-4" /></button>
          <button onClick={onDelete} aria-label={t.common.delete} className="rounded-md p-1.5 text-ink-400 hover:bg-bad-50 hover:text-bad-600"><Trash2 className="size-4" /></button>
        </div>
      </div>
    </div>
  )
}

function fieldErrorsOf(err: unknown): Record<string, string> | null {
  const errors = (err as { response?: { data?: ApiError } }).response?.data?.errors
  return errors ? Object.fromEntries(Object.entries(errors).map(([k, v]) => [k, v[0]])) : null
}

function ProductModal({
  item, categories, defaultCategory, onClose, onSaved,
}: {
  item: MenuItem | null; categories: MenuCategory[]; defaultCategory: string
  onClose: () => void; onSaved: () => void
}) {
  const t = useT()
  const c = t.grocery.catalog
  const fileRef = useRef<HTMLInputElement>(null)
  const [error, setError] = useState<string | null>(null)
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})
  const [form, setForm] = useState<ProductForm>(item ? {
    name_ar: item.name_ar, name_en: item.name_en ?? '', description_ar: item.description ?? '',
    category_id: item.category_id ? String(item.category_id) : '',
    price: String(item.price), compare_at_price: item.compare_at_price != null ? String(item.compare_at_price) : '',
    unit: item.unit ?? '', stock_quantity: item.stock_quantity != null ? String(item.stock_quantity) : '',
    is_featured: item.is_featured,
  } : { ...EMPTY_PRODUCT, category_id: defaultCategory })

  const save = useMutation({
    mutationFn: async () => {
      const body = {
        name_ar: form.name_ar,
        name_en: form.name_en || null,
        description_ar: form.description_ar || null,
        menu_category_id: form.category_id ? Number(form.category_id) : null,
        price: Number(form.price),
        compare_at_price: form.compare_at_price === '' ? null : Number(form.compare_at_price),
        unit: form.unit || null,
        stock_quantity: form.stock_quantity === '' ? null : Number(form.stock_quantity),
        is_featured: form.is_featured,
      }
      const saved = item
        ? (await api.put<MenuItem>(`/merchant/menu/items/${item.id}`, body)).data
        : (await api.post<MenuItem>('/merchant/menu/items', body)).data
      const file = fileRef.current?.files?.[0]
      if (file) {
        const fd = new FormData()
        fd.append('image', file)
        await api.post(`/merchant/menu/items/${saved.id}/image`, fd)
      }
    },
    onSuccess: onSaved,
    onError: (err) => {
      const fe = fieldErrorsOf(err)
      if (fe) setFieldErrors(fe)
      else setError(errorMessage(err, t.common.error))
    },
  })

  const set = <K extends keyof ProductForm>(key: K, value: ProductForm[K]) => setForm((f) => ({ ...f, [key]: value }))
  const selectCls = 'h-10 w-full rounded-lg border border-ink-200 bg-white px-3 text-sm'

  return (
    <Modal
      open
      onClose={onClose}
      title={item ? c.edit : c.add}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>{t.common.cancel}</Button>
          <Button className="bg-fresh-700 hover:bg-fresh-800" loading={save.isPending} onClick={() => { setFieldErrors({}); save.mutate() }}>
            {t.common.save}
          </Button>
        </>
      }
    >
      <div className="space-y-4">
        {error && <p className="text-sm text-bad-600">{error}</p>}
        <div className="grid grid-cols-2 gap-3">
          <Input label={c.name} value={form.name_ar} error={fieldErrors.name_ar} onChange={(e) => set('name_ar', e.target.value)} />
          <Input label={c.nameEn} dir="ltr" value={form.name_en} onChange={(e) => set('name_en', e.target.value)} />
        </div>
        <label className="block">
          <span className="mb-1.5 block text-[13px] font-medium text-ink-700">{c.category}</span>
          <select value={form.category_id} onChange={(e) => set('category_id', e.target.value)} className={selectCls}>
            <option value="">{c.uncategorised}</option>
            {categories.map((cat) => <option key={cat.id} value={cat.id}>{cat.name_ar}</option>)}
          </select>
        </label>
        <div className="grid grid-cols-2 gap-3">
          <Input label={c.price} type="number" min={0} step="0.01" value={form.price} error={fieldErrors.price}
            onChange={(e) => set('price', e.target.value)} />
          <Input label={c.compareAt} type="number" min={0} step="0.01" value={form.compare_at_price}
            error={fieldErrors.compare_at_price} hint={fieldErrors.compare_at_price ? undefined : c.compareAtHint}
            onChange={(e) => set('compare_at_price', e.target.value)} />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Input label={c.unit} placeholder={c.unitPlaceholder} value={form.unit} onChange={(e) => set('unit', e.target.value)} />
          <Input label={c.stock} type="number" min={0} step="1" value={form.stock_quantity} hint={c.stockHint}
            onChange={(e) => set('stock_quantity', e.target.value)} />
        </div>
        <Input label={c.description} value={form.description_ar} onChange={(e) => set('description_ar', e.target.value)} />
        <label className="flex items-center gap-2 rounded-lg border border-ink-200 px-3 py-2.5 text-sm text-ink-800">
          <input type="checkbox" checked={form.is_featured} onChange={(e) => set('is_featured', e.target.checked)} className="size-4 accent-fresh-700" />
          <Star className={cn('size-4', form.is_featured ? 'fill-warn-600 text-warn-600' : 'text-ink-300')} />
          {c.bestSeller}
        </label>
        <label className="block">
          <span className="mb-1.5 flex items-center gap-1.5 text-[13px] font-medium text-ink-700"><ImagePlus className="size-4" /> {c.image}</span>
          <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" className="block w-full text-sm text-ink-600" />
        </label>
      </div>
    </Modal>
  )
}

function CategoryModal({ category, onClose, onSaved }: { category: MenuCategory | null; onClose: () => void; onSaved: () => void }) {
  const t = useT()
  const c = t.grocery.catalog
  const fileRef = useRef<HTMLInputElement>(null)
  const [error, setError] = useState<string | null>(null)
  const [form, setForm] = useState({ name_ar: category?.name_ar ?? '', name_en: category?.name_en ?? '' })

  const save = useMutation({
    mutationFn: async () => {
      const body = { name_ar: form.name_ar, name_en: form.name_en || null }
      const saved = category
        ? (await api.put<MenuCategory>(`/merchant/menu/categories/${category.id}`, body)).data
        : (await api.post<MenuCategory>('/merchant/menu/categories', body)).data
      const file = fileRef.current?.files?.[0]
      if (file) {
        const fd = new FormData()
        fd.append('image', file)
        await api.post(`/merchant/menu/categories/${saved.id}/image`, fd)
      }
    },
    onSuccess: onSaved,
    onError: (err) => setError(errorMessage(err, t.common.error)),
  })

  return (
    <Modal
      open
      onClose={onClose}
      title={category ? c.editCategory : c.addCategory}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>{t.common.cancel}</Button>
          <Button className="bg-fresh-700 hover:bg-fresh-800" loading={save.isPending} onClick={() => save.mutate()}>{t.common.save}</Button>
        </>
      }
    >
      <div className="space-y-4">
        {error && <p className="text-sm text-bad-600">{error}</p>}
        <Input label={c.categoryName} value={form.name_ar} onChange={(e) => setForm({ ...form, name_ar: e.target.value })} />
        <Input label={c.categoryNameEn} dir="ltr" value={form.name_en} onChange={(e) => setForm({ ...form, name_en: e.target.value })} />
        <label className="block">
          <span className="mb-1.5 block text-[13px] font-medium text-ink-700">{c.categoryImage}</span>
          <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" className="block w-full text-sm text-ink-600" />
        </label>
      </div>
    </Modal>
  )
}
