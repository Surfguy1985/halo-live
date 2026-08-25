/**
 * B5 Service ETA stack — multi-day dependent trades + cure as first-class state
 * Cure = shimmer band + countdown, NEVER a spinner
 */
import { cn } from '@/lib/cn'

export type EtaRow =
  | {
      kind: 'done'
      id: string
      title: string
      crew?: string
      detail: string
    }
  | {
      kind: 'progress'
      id: string
      title: string
      crew: string
      finishBy: string
    }
  | {
      kind: 'waiting'
      id: string
      title: string
      crew?: string
      after: string
    }
  | {
      kind: 'cure'
      id: string
      scale: 'short' | 'long'
      title: string
      remaining: string
      reopens: string
      reason: string
    }

export type EtaDay = {
  label: string
  rows: EtaRow[]
}

export function ServiceEtaStack({
  days,
  summary,
  summaryWarn,
}: {
  days: EtaDay[]
  summary: string
  summaryWarn?: boolean
}) {
  return (
    <div className="space-y-5">
      <div
        className={cn(
          'mono text-[13px] font-semibold px-1',
          summaryWarn ? 'text-warn' : 'text-text-muted',
        )}
      >
        {summary}
      </div>

      {days.map((day) => (
        <div key={day.label}>
          <div className="mono text-[10px] uppercase tracking-[0.16em] text-text-muted mb-3 px-1">
            {day.label}
          </div>
          <div className="relative pl-1">
            {/* vertical connector */}
            <div className="absolute left-[11px] top-2 bottom-2 w-px bg-line" />
            <div className="space-y-3">
              {day.rows.map((row) => (
                <EtaRowView key={row.id} row={row} />
              ))}
            </div>
          </div>
        </div>
      ))}
    </div>
  )
}

function EtaRowView({ row }: { row: EtaRow }) {
  if (row.kind === 'cure') {
    if (row.scale === 'long') {
      return (
        <div className="relative z-[1] rounded-[16px] border border-ink-line/30 overflow-hidden cure-band p-4 ml-0">
          <div className="flex items-start gap-3">
            <span className="mt-0.5 h-5 w-5 rounded-full border-2 border-warn/80 bg-paper shrink-0 grid place-items-center">
              <span className="h-2 w-2 rounded-full bg-warn" />
            </span>
            <div className="flex-1 min-w-0">
              <div className="text-[14px] font-semibold text-ink">Unit closed — curing</div>
              <div className="mt-0.5 text-[13px] text-text-muted leading-snug">
                Nobody on site. {row.reason}. Reopens {row.reopens}.
              </div>
              <div className="mono mt-2 text-[15px] font-semibold text-warn">{row.remaining} remaining</div>
            </div>
          </div>
        </div>
      )
    }
    return (
      <div className="relative z-[1] ml-7 rounded-[10px] bg-line/60 px-3 py-2.5">
        <div className="flex items-center gap-2">
          <span className="h-2.5 w-2.5 rounded-full bg-warn/70 shrink-0" />
          <span className="text-[13px] text-text-muted">
            Unit closed while {row.reason} · until {row.reopens}
          </span>
        </div>
      </div>
    )
  }

  const node =
    row.kind === 'done' ? (
      <span className="h-5 w-5 rounded-full bg-ok grid place-items-center shrink-0 relative z-[1]">
        <span className="text-white text-[10px] font-bold">✓</span>
      </span>
    ) : row.kind === 'progress' ? (
      <span className="h-5 w-5 rounded-full bg-live-dark relative z-[1] shrink-0">
        <span className="absolute inset-0 rounded-full bg-live-dark live-dot opacity-80" />
      </span>
    ) : (
      <span className="h-5 w-5 rounded-full border-2 border-line bg-paper shrink-0 relative z-[1]" />
    )

  return (
    <div className="relative flex gap-3 items-start">
      {node}
      <div className={cn('flex-1 min-w-0 pb-1', row.kind === 'done' && 'opacity-60')}>
        <div className="flex justify-between gap-2">
          <div className="text-[15px] font-semibold text-ink leading-snug">{row.title}</div>
          {row.kind === 'progress' && (
            <div className="mono text-[12px] font-semibold text-ink shrink-0">by {row.finishBy}</div>
          )}
        </div>
        {row.kind === 'done' && (
          <div className="text-[13px] text-text-muted mt-0.5">
            {row.crew ? `${row.crew} · ` : ''}
            {row.detail}
          </div>
        )}
        {row.kind === 'progress' && (
          <div className="text-[13px] text-live-dark font-medium mt-0.5">{row.crew} · in progress</div>
        )}
        {row.kind === 'waiting' && (
          <div className="text-[13px] text-text-muted mt-0.5">
            {row.crew ? `${row.crew} · ` : ''}
            after {row.after}
          </div>
        )}
      </div>
    </div>
  )
}
