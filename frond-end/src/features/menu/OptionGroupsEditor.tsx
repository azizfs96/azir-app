import { Plus, X } from 'lucide-react'
import { useT } from '@/app/i18n'
import { Button } from '@/components/ui/Button'
import { cn } from '@/lib/cn'

/**
 * ============================================================================
 * THE OPTION-TREE EDITOR — size / extras / sauces for one dish.
 *
 * Mirrors the Jahez model the backend already validates: a group has a
 * min/max selection count (min 1,max 1 = required single choice; min 0 = extras)
 * and 1..N options each carrying a signed price delta. The whole tree is saved
 * in one PUT — the server replaces it atomically.
 * ============================================================================
 */

export interface OptionDraft {
  name_ar: string
  price_delta: string
}

export interface GroupDraft {
  name_ar: string
  min_select: number
  max_select: number
  options: OptionDraft[]
}

export function emptyGroup(): GroupDraft {
  return { name_ar: '', min_select: 1, max_select: 1, options: [{ name_ar: '', price_delta: '0' }] }
}

/** True when the tree is fulfillable — matches the server's own refusal rule. */
export function groupsAreValid(groups: GroupDraft[]): boolean {
  return groups.every(
    (g) =>
      g.name_ar.trim() !== '' &&
      g.options.length >= 1 &&
      g.options.every((o) => o.name_ar.trim() !== '') &&
      g.min_select <= g.max_select &&
      g.min_select <= g.options.length,
  )
}

export function OptionGroupsEditor({
  groups, onChange,
}: {
  groups: GroupDraft[]
  onChange: (groups: GroupDraft[]) => void
}) {
  const t = useT()
  const m = t.menuPage

  const patchGroup = (gi: number, patch: Partial<GroupDraft>) =>
    onChange(groups.map((g, i) => (i === gi ? { ...g, ...patch } : g)))

  const patchOption = (gi: number, oi: number, patch: Partial<OptionDraft>) =>
    patchGroup(gi, {
      options: groups[gi].options.map((o, i) => (i === oi ? { ...o, ...patch } : o)),
    })

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <div>
          <p className="text-[13px] font-medium text-ink-700">{m.options}</p>
          <p className="text-xs text-ink-400">{m.optionsHint}</p>
        </div>
        <Button size="sm" variant="secondary" onClick={() => onChange([...groups, emptyGroup()])}>
          <Plus className="size-3.5" />
          {m.addGroup}
        </Button>
      </div>

      {groups.map((group, gi) => (
        <div key={gi} className="rounded-lg border border-ink-200 bg-ink-50 p-3">
          <div className="flex items-center gap-2">
            <input
              value={group.name_ar}
              placeholder={m.groupName}
              onChange={(e) => patchGroup(gi, { name_ar: e.target.value })}
              className="h-9 flex-1 rounded-lg border border-ink-200 bg-white px-3 text-sm"
            />
            <button
              onClick={() => onChange(groups.filter((_, i) => i !== gi))}
              aria-label={t.common.delete}
              className="rounded-md p-1.5 text-ink-400 hover:bg-bad-50 hover:text-bad-600"
            >
              <X className="size-4" />
            </button>
          </div>

          <div className="mt-2 flex items-center gap-3 text-xs text-ink-600">
            <label className="flex items-center gap-1">
              {m.minSelect}
              <input
                type="number" min={0} max={group.options.length}
                value={group.min_select}
                onChange={(e) => patchGroup(gi, { min_select: Math.max(0, Number(e.target.value)) })}
                className="h-8 w-14 rounded-md border border-ink-200 bg-white px-2 tabular-nums"
              />
            </label>
            <label className="flex items-center gap-1">
              {m.maxSelect}
              <input
                type="number" min={1} max={group.options.length}
                value={group.max_select}
                onChange={(e) => patchGroup(gi, { max_select: Math.max(1, Number(e.target.value)) })}
                className="h-8 w-14 rounded-md border border-ink-200 bg-white px-2 tabular-nums"
              />
            </label>
            <span
              className={cn(
                'rounded-md px-2 py-0.5 font-medium',
                group.min_select > 0 ? 'bg-brand-50 text-brand-600' : 'bg-ink-100 text-ink-500',
              )}
            >
              {group.min_select > 0 ? m.required : m.options}
            </span>
          </div>

          <ul className="mt-2 space-y-1.5">
            {group.options.map((option, oi) => (
              <li key={oi} className="flex items-center gap-2">
                <input
                  value={option.name_ar}
                  placeholder={m.optionName}
                  onChange={(e) => patchOption(gi, oi, { name_ar: e.target.value })}
                  className="h-8 flex-1 rounded-md border border-ink-200 bg-white px-2 text-sm"
                />
                <input
                  type="number" step="0.5"
                  value={option.price_delta}
                  title={m.priceDelta}
                  onChange={(e) => patchOption(gi, oi, { price_delta: e.target.value })}
                  className="h-8 w-20 rounded-md border border-ink-200 bg-white px-2 text-sm tabular-nums"
                />
                {group.options.length > 1 && (
                  <button
                    onClick={() =>
                      patchGroup(gi, { options: group.options.filter((_, i) => i !== oi) })
                    }
                    aria-label={t.common.delete}
                    className="rounded-md p-1 text-ink-400 hover:bg-bad-50 hover:text-bad-600"
                  >
                    <X className="size-3.5" />
                  </button>
                )}
              </li>
            ))}
          </ul>

          <button
            onClick={() => patchGroup(gi, { options: [...group.options, { name_ar: '', price_delta: '0' }] })}
            className="mt-2 text-xs font-medium text-brand-600 hover:underline"
          >
            + {m.addOption}
          </button>
        </div>
      ))}
    </div>
  )
}
