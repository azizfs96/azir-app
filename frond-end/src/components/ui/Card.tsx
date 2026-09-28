import { cn } from '@/lib/cn'
import type { ReactNode } from 'react'

/**
 * A surface. Hairline border, no shadow (spec §32: "avoid excessive cards").
 * Used for genuine grouping only, never as decoration.
 */
export function Card({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <div className={cn('rounded-[10px] border border-ink-200 bg-white', className)}>
      {children}
    </div>
  )
}

export function CardHeader({ title, action }: { title: ReactNode; action?: ReactNode }) {
  return (
    <div className="flex items-center justify-between border-b border-ink-200 px-5 py-3.5">
      <h2 className="text-sm font-semibold text-ink-900">{title}</h2>
      {action}
    </div>
  )
}
