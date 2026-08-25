import { cn } from '@/lib/cn'

const STYLES: Record<string, string> = {
  open: 'bg-black/5 text-ink',
  in_progress: 'bg-live/20 text-live-dark',
  review: 'bg-warn/15 text-warn',
  approved: 'bg-ok/15 text-ok',
  flagged: 'bg-danger/10 text-danger',
  done: 'bg-ok/15 text-ok',
}

export function StatusChip({ status, className }: { status: string; className?: string }) {
  const label = status.replace(/_/g, ' ')
  return (
    <span
      className={cn(
        'shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide',
        STYLES[status] || 'bg-black/5 text-text-muted',
        className,
      )}
    >
      {label}
    </span>
  )
}
