import type { ButtonHTMLAttributes, ReactNode } from 'react'
import { cn } from '@/lib/cn'

export function PrimaryCTA({
  children,
  className,
  variant = 'gold',
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  children: ReactNode
  variant?: 'gold' | 'ink' | 'ghost' | 'live'
}) {
  return (
    <button
      type="button"
      className={cn(
        'press w-full rounded-full font-bold text-[16px] py-[15px] tracking-[-0.01em]',
        'disabled:opacity-40 disabled:pointer-events-none',
        'shadow-[0_1px_0_rgba(255,255,255,0.12)_inset]',
        variant === 'gold' && 'bg-gold text-ink hover:brightness-105',
        variant === 'ink' && 'bg-ink text-white',
        variant === 'ghost' && 'bg-transparent text-slate border border-ink-line shadow-none',
        variant === 'live' && 'bg-live text-ink',
        className,
      )}
      {...props}
    >
      {children}
    </button>
  )
}
