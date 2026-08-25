import type { ReactNode } from 'react'
import { cn } from '@/lib/cn'

export type SheetSnap = 'peek' | 'half' | 'full'

const HEIGHT: Record<SheetSnap, string> = {
  peek: '28vh',
  half: '52vh',
  full: '88vh',
}

export function Sheet({
  snap = 'half',
  onSnapChange,
  onSnap,
  children,
  className,
  light = true,
}: {
  snap?: SheetSnap
  onSnapChange?: (s: SheetSnap) => void
  onSnap?: (s: SheetSnap) => void
  children: ReactNode
  className?: string
  light?: boolean
}) {
  const setSnap = onSnapChange || onSnap

  function cycle() {
    if (!setSnap) return
    const order: SheetSnap[] = ['peek', 'half', 'full']
    const i = order.indexOf(snap)
    setSnap(order[(i + 1) % order.length])
  }

  return (
    <div
      className={cn(
        'absolute inset-x-0 bottom-0 z-30 flex flex-col rounded-t-[24px] shadow-[0_-8px_40px_rgba(0,0,0,0.12)] transition-[height] duration-300 ease-[cubic-bezier(0.2,0.7,0.2,1)]',
        light ? 'bg-white text-ink' : 'bg-ink-raised text-[#F2F5FA] border-t border-ink-line',
        className,
      )}
      style={{ height: HEIGHT[snap] }}
    >
      <button type="button" onClick={cycle} className="flex justify-center pt-2.5 pb-1 shrink-0" aria-label="Resize sheet">
        <div className={cn('h-[5px] w-9 rounded-full', light ? 'bg-black/15' : 'bg-white/20')} />
      </button>
      <div className="flex-1 overflow-y-auto overscroll-contain min-h-0">{children}</div>
    </div>
  )
}
