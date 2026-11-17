import { cn } from '@/lib/cn'

/** A labelled switch row. The knob uses start-/end- so it sits correctly in RTL. */
export function Toggle({
  label, hint, checked, onChange, disabled,
}: { label: string; hint?: string; checked: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <div className="flex items-start justify-between gap-4 px-5 py-3.5">
      <div className="min-w-0">
        <div className="text-sm text-ink-900">{label}</div>
        {hint && <div className="mt-0.5 text-xs text-ink-500">{hint}</div>}
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={cn(
          'relative h-5 w-9 shrink-0 rounded-full transition-colors disabled:opacity-50',
          checked ? 'bg-ink-900' : 'bg-ink-200',
        )}
      >
        <span className={cn(
          'absolute top-0.5 size-4 rounded-full bg-white transition-all',
          checked ? 'start-[18px]' : 'start-0.5',
        )} />
      </button>
    </div>
  )
}
