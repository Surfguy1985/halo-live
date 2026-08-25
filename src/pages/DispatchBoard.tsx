/**
 * D2 · Dispatch board — real crew roster + jobs when Halo is up
 */
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { PrimaryCTA } from '@/components/PrimaryCTA'
import { cn } from '@/lib/cn'
import { loadSharedOrder, queueCrewPing } from '@/lib/orderBus'
import { useNavigate } from 'react-router-dom'
import { getPlate, getWorkItems, getRoleFromStorage, type WorkItem } from '@/lib/api'

type Row =
  | { kind: 'job'; id: string; name: string; duration: string; price: string; crew: string | null }
  | { kind: 'cure'; id: string; label: string; note: string }

const FALLBACK_ROWS: Row[] = [
  { kind: 'job', id: 'trash', name: 'Trash Out', duration: '2h', price: '$85', crew: 'Sam K' },
  { kind: 'job', id: 'rock', name: 'Sheetrock Repair', duration: '4h', price: '$185', crew: null },
  { kind: 'cure', id: 'cure-mud', label: 'Unit closed · mud curing', note: 'Overnight · reopens Tue 7:00 AM · nothing to assign' },
  { kind: 'job', id: 'kilz', name: 'Kilz Primer Seal', duration: '2h', price: '$120', crew: null },
  { kind: 'job', id: 'paint', name: 'Wall Prep & Paint', duration: '4h', price: '$230', crew: null },
  { kind: 'cure', id: 'cure-paint', label: 'Unit closed · paint setting', note: '3h · schedule follow-on after 3:00 PM' },
  { kind: 'job', id: 'clean', name: 'Vacant Unit Clean', duration: '1.5h', price: '$150', crew: null },
]

const FALLBACK_CREW = ['Jose M', 'Marco R', 'Kaynne T', 'Sam K']

export default function DispatchBoard() {
  const nav = useNavigate()
  const shared = loadSharedOrder()
  const unitLabel = shared?.unit || '1713'
  const [rows, setRows] = useState<Row[]>(FALLBACK_ROWS)
  const [crewNames, setCrewNames] = useState<string[]>(FALLBACK_CREW)
  const [live, setLive] = useState(false)
  const [assignId, setAssignId] = useState<string | null>(null)
  const [sent, setSent] = useState(false)
  const [idleHint, setIdleHint] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      const role = getRoleFromStorage() || 'vendor'
      const [plate, work] = await Promise.all([getPlate(role), getWorkItems()])
      if (cancelled) return

      if (plate.crew.length) {
        setCrewNames(plate.crew.map((c) => c.name).filter(Boolean))
        const free = plate.crew.find((c) => c.status !== 'on_site') || plate.crew[0]
        if (free) {
          setIdleHint(
            `${free.name} is available. Unit ${unitLabel} may be in cure — reassign to another open unit.`,
          )
        }
        setLive(true)
      }

      if (work.items.length) {
        const unitJobs = work.items.filter(
          (i) => String(i.unit || '').includes(unitLabel) || !shared?.unit,
        )
        const source = unitJobs.length ? unitJobs : work.items.slice(0, 6)
        const built: Row[] = source.map((j: WorkItem) => ({
          kind: 'job' as const,
          id: j.id,
          name: j.services?.length ? j.services.join(' · ') : j.title,
          duration: '—',
          price: j.poNumber ? `PO ${j.poNumber}` : '—',
          crew: j.assignedTo || null,
        }))
        if (built.length) {
          // Keep one illustrative cure band at top if shared order has curing services
          const hasCure = shared?.lines.some((l) => l.cureHours >= 12)
          const next: Row[] = hasCure
            ? [
                {
                  kind: 'cure',
                  id: 'cure-live',
                  label: `Unit ${unitLabel} · cure window`,
                  note: 'Chemistry in progress · no crew on this slot',
                },
                ...built,
              ]
            : built
          setRows(next)
          setLive(true)
        }
      }
    })()
    return () => {
      cancelled = true
    }
  }, [unitLabel, shared?.unit])

  const openJobs = rows.filter((r) => r.kind === 'job') as Extract<Row, { kind: 'job' }>[]
  const unassigned = openJobs.filter((j) => !j.crew).length

  function assign(jobId: string, name: string) {
    setRows((prev) =>
      prev.map((r) => (r.kind === 'job' && r.id === jobId ? { ...r, crew: name } : r)),
    )
    setAssignId(null)
  }

  return (
    <div className="min-h-full bg-ink text-[#F2F5FA] page-enter max-w-lg mx-auto flex flex-col">
      <header className="px-[22px] pt-[max(1rem,env(safe-area-inset-top))] pb-3 border-b border-ink-line">
        <div className="flex items-center justify-between">
          <div className="text-[11px] mono uppercase tracking-[0.16em] text-slate-dim">Dispatch</div>
          {live && <span className="text-[10px] mono text-live">Live roster</span>}
        </div>
        <h1 className="text-[28px] font-bold tracking-[-0.03em]">{`Unit ${unitLabel}`}</h1>
        <p className="text-[14px] text-slate mt-1">
          {unassigned === 0 ? 'All services assigned' : `${unassigned} need a crew`}
          {live ? ' · Halo jobs' : ' · demo board'}
        </p>
      </header>

      <main className="flex-1 px-[22px] py-4 space-y-3 pb-36">
        {idleHint && (
          <div className="rounded-[16px] border border-live/30 bg-live/5 p-4">
            <div className="text-[14px] font-semibold text-live">Crew available during cure</div>
            <p className="mt-1 text-[13px] text-slate leading-snug">{idleHint}</p>
          </div>
        )}

        {/* Live crew chips */}
        <div className="flex gap-2 overflow-x-auto no-scrollbar pb-1">
          {crewNames.map((c) => (
            <div
              key={c}
              className="shrink-0 flex items-center gap-2 rounded-full bg-ink-raised border border-ink-line pl-1 pr-3 py-1"
            >
              <div className="h-7 w-7 rounded-full bg-gold text-ink grid place-items-center text-[10px] font-bold">
                {c.split(' ').map((w) => w[0]).join('').slice(0, 2)}
              </div>
              <span className="text-[12px] font-medium">{c}</span>
            </div>
          ))}
        </div>

        {rows.map((r) =>
          r.kind === 'cure' ? (
            <div key={r.id} className="rounded-[16px] cure-band border border-ink-line p-4">
              <div className="text-[14px] font-semibold">{r.label}</div>
              <div className="text-[12px] text-slate mt-1">{r.note}</div>
            </div>
          ) : (
            <div key={r.id} className="rounded-[16px] bg-ink-raised border border-ink-line p-4">
              <div className="flex justify-between gap-3">
                <div className="min-w-0">
                  <div className="text-[16px] font-semibold leading-snug">{r.name}</div>
                  <div className="mono text-[12px] text-slate-dim mt-0.5">
                    {r.duration} · {r.price}
                  </div>
                </div>
                {r.crew ? (
                  <div className="flex items-center gap-2 shrink-0">
                    <div className="h-8 w-8 rounded-full bg-gold text-ink grid place-items-center text-[11px] font-bold">
                      {r.crew.split(' ').map((w) => w[0]).join('').slice(0, 2)}
                    </div>
                    <span className="text-[13px] font-medium">{r.crew}</span>
                  </div>
                ) : (
                  <button
                    type="button"
                    onClick={() => setAssignId(r.id)}
                    className="press rounded-full border border-gold text-gold text-[13px] font-bold px-4 py-2 shrink-0"
                  >
                    Assign
                  </button>
                )}
              </div>
              {assignId === r.id && (
                <div className="mt-3 flex flex-wrap gap-2">
                  {crewNames.map((c) => (
                    <button
                      key={c}
                      type="button"
                      onClick={() => assign(r.id, c)}
                      className="press rounded-full bg-ink-hover border border-ink-line px-3 py-1.5 text-[13px] font-medium"
                    >
                      {c}
                    </button>
                  ))}
                </div>
              )}
            </div>
          ),
        )}
      </main>

      <div className="fixed bottom-0 inset-x-0 max-w-lg mx-auto p-4 pb-[max(1rem,env(safe-area-inset-bottom))] bg-ink border-t border-ink-line">
        {sent ? (
          <div className="space-y-2">
            <p className="text-center text-[15px] text-ok font-semibold py-1">
              {openJobs.length} pings queued
            </p>
            <PrimaryCTA onClick={() => nav('/crew/ping')}>Open first crew ping</PrimaryCTA>
          </div>
        ) : (
          <PrimaryCTA
            disabled={unassigned > 0}
            onClick={() => {
              const assigned = openJobs.filter((j) => j.crew)
              const first = assigned[0]
              if (first) {
                queueCrewPing({
                  serviceName: first.name,
                  unit: unitLabel,
                  property: shared?.property || 'Thornbury at Chase Oaks',
                  priceCents: 23000,
                  crewName: first.crew || 'Crew',
                  jobId: first.id,
                })
              }
              setSent(true)
            }}
          >
            {unassigned > 0 ? `Assign ${unassigned} more` : `Send ${openJobs.length} pings`}
          </PrimaryCTA>
        )}
        <Link to="/live" className="block text-center text-[13px] text-slate mt-2 py-1">
          Live map · crew GPS
        </Link>
      </div>
    </div>
  )
}
