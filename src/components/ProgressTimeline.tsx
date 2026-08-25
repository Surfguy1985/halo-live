import { cn } from '@/lib/cn'

export interface TimelineStep {
  id: string
  label: string
  done?: boolean
  current?: boolean
}

/** DoorDash-style linear track: dots + labels */
export function ProgressTimeline({ steps }: { steps: TimelineStep[] }) {
  return (
    <div className="mt-4 mb-1">
      <div className="flex items-center gap-0">
        {steps.map((s, i) => {
          const active = s.done || s.current
          return (
            <div key={s.id} className="flex items-center flex-1 last:flex-none">
              <div
                className={cn(
                  'h-2.5 w-2.5 rounded-full shrink-0 border-2 transition-colors',
                  s.done && 'bg-ink border-ink',
                  s.current && !s.done && 'bg-lime border-ink scale-110',
                  !active && 'bg-white border-black/20',
                )}
              />
              {i < steps.length - 1 && (
                <div
                  className={cn(
                    'h-0.5 flex-1 mx-1 rounded-full transition-colors',
                    s.done ? 'bg-ink' : 'bg-black/10',
                  )}
                />
              )}
            </div>
          )
        })}
      </div>
      <div className="mt-1.5 flex justify-between">
        {steps.map((s) => (
          <span
            key={s.id}
            className={cn(
              'text-[10px] font-medium',
              s.current ? 'text-ink' : 'text-slate-dim',
            )}
          >
            {s.label}
          </span>
        ))}
      </div>
    </div>
  )
}
