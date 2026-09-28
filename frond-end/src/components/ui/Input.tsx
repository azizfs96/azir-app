import { cn } from '@/lib/cn'
import type { InputHTMLAttributes, ReactNode } from 'react'

interface Props extends InputHTMLAttributes<HTMLInputElement> {
  label?: ReactNode
  hint?: ReactNode
  error?: string | null
}

export function Input({ label, hint, error, className, id, ...props }: Props) {
  const inputId = id ?? props.name

  return (
    <label className="block" htmlFor={inputId}>
      {label && (
        <span className="mb-1.5 block text-[13px] font-medium text-ink-700">{label}</span>
      )}
      <input
        id={inputId}
        className={cn(
          'h-10 w-full rounded-lg border bg-white px-3 text-sm text-ink-900',
          'placeholder:text-ink-400 transition-colors',
          error ? 'border-bad-600' : 'border-ink-200 hover:border-ink-300',
          className,
        )}
        {...props}
      />
      {error
        ? <span className="mt-1 block text-xs text-bad-600">{error}</span>
        : hint && <span className="mt-1 block text-xs text-ink-500">{hint}</span>}
    </label>
  )
}
