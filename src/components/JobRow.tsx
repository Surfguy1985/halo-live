/**
 * Uber "Choose a ride" row — selected = thick border
 */
import type { WorkItem } from '@/lib/api'
import { cn } from '@/lib/cn'
import { StatusChip } from '@/components/StatusChip'

export function JobRow({
  job,
  selected,
  onClick,
}: {
  job: WorkItem
  selected?: boolean
  onClick?: () => void
}) {
  const services = job.services?.length
    ? job.services.join(' · ')
    : job.title.split('\n')[0]

  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'press w-full text-left rounded-[16px] px-4 py-3.5 transition-all duration-150',
        selected
          ? 'border-[2.5px] border-ink bg-white shadow-[0_2px_12px_rgba(0,0,0,0.06)]'
          : 'border border-transparent hover:bg-black/[0.03]',
      )}
    >
      <div className="flex items-center gap-3">
        <div
          className={cn(
            'shrink-0 h-14 w-14 rounded-[12px] flex flex-col items-center justify-center',
            selected ? 'bg-ink text-gold' : 'bg-[#F0F0EA] text-ink',
          )}
        >
          <span className="text-[9px] font-semibold uppercase tracking-[0.12em] opacity-60">Unit</span>
          <span className="mono text-[16px] font-bold leading-none mt-0.5">{job.unit}</span>
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2">
            <div className="min-w-0">
              <div className="text-[15px] font-semibold tracking-[-0.01em] line-clamp-1">{services}</div>
              <div className="mt-0.5 text-[13px] text-text-muted line-clamp-1">
                {job.assignedTo || 'Unassigned'}
                {job.jobNo ? ` · ${job.jobNo}` : ''}
              </div>
            </div>
            <StatusChip status={job.status} />
          </div>
        </div>
      </div>
    </button>
  )
}
