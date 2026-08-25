/**
 * Base44-style job facts: Unit · Services · Crew
 */
import { HardHat, MapPin, Wrench } from 'lucide-react'
import type { WorkItem } from '@/lib/api'
import { cn } from '@/lib/cn'

export function JobFacts({
  job,
  dense = false,
  className,
}: {
  job: WorkItem
  dense?: boolean
  className?: string
}) {
  const services =
    job.services?.length > 0
      ? job.services
      : job.title
        ? [job.title.split('\n')[0]]
        : []

  return (
    <div className={cn('space-y-1.5', className)}>
      {/* Unit — most prominent like Base44 */}
      <div className="flex items-center gap-1.5">
        <MapPin className={cn('shrink-0 text-slate-dim', dense ? 'h-3 w-3' : 'h-3.5 w-3.5')} />
        <span className={cn('font-bold text-ink tabular-nums', dense ? 'text-[13px]' : 'text-[15px]')}>
          Unit {job.unit || '—'}
        </span>
        {job.jobNo && (
          <span className="text-[11px] text-slate-dim font-medium">· {job.jobNo}</span>
        )}
      </div>

      {/* Services */}
      <div className="flex items-start gap-1.5">
        <Wrench className={cn('shrink-0 text-slate-dim mt-0.5', dense ? 'h-3 w-3' : 'h-3.5 w-3.5')} />
        <div className="min-w-0 flex-1">
          {services.length === 0 ? (
            <span className="text-[12px] text-slate-dim">No services listed</span>
          ) : dense ? (
            <span className="text-[12px] text-ink line-clamp-2">{services.join(' · ')}</span>
          ) : (
            <ul className="flex flex-wrap gap-1">
              {services.map((s) => (
                <li
                  key={s}
                  className="rounded-full bg-black/[0.05] border border-black/[0.06] px-2 py-0.5 text-[11px] font-medium text-ink"
                >
                  {s}
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      {/* Crew */}
      <div className="flex items-center gap-1.5">
        <HardHat className={cn('shrink-0 text-slate-dim', dense ? 'h-3 w-3' : 'h-3.5 w-3.5')} />
        <span className={cn(dense ? 'text-[12px]' : 'text-[13px]', job.assignedTo ? 'text-ink font-medium' : 'text-slate-dim')}>
          {job.assignedTo || 'Unassigned'}
        </span>
        {job.propertyName && !dense && (
          <span className="text-[11px] text-slate-dim truncate">· {job.propertyName}</span>
        )}
      </div>
    </div>
  )
}
