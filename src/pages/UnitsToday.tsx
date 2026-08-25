/**
 * A1 · Today's units — Field Manager (dark)
 * Uber Services-style 2-col grid
 */
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { setWalkUnit } from '@/lib/catalog'
import { getWorkItems } from '@/lib/api'
import { PrimaryCTA } from '@/components/PrimaryCTA'

type UnitCard = { unit: string; bedrooms: number; property: string; status: string; photo: null }

const FALLBACK_UNITS: UnitCard[] = [
  { unit: '1713', bedrooms: 1, property: 'Thornbury at Chase Oaks', status: 'Not walked', photo: null },
  { unit: '2321', bedrooms: 2, property: 'Thornbury at Chase Oaks', status: 'Order sent', photo: null },
  { unit: '911', bedrooms: 1, property: 'Thornbury at Chase Oaks', status: 'Approved', photo: null },
  { unit: '713', bedrooms: 3, property: 'Thornbury at Chase Oaks', status: 'In progress', photo: null },
]

const STATUS_STYLE: Record<string, string> = {
  'Not walked': 'bg-ink-hover text-slate',
  'Order sent': 'bg-ink-hover text-gold',
  'Approved': 'bg-ok/20 text-ok',
  'In progress': 'bg-live/15 text-live',
}

export default function UnitsToday() {
  const nav = useNavigate()
  const [units, setUnits] = useState<UnitCard[]>(FALLBACK_UNITS)
  const [live, setLive] = useState(false)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      const { items } = await getWorkItems()
      if (cancelled || !items.length) return
      const seen = new Set<string>()
      const cards: UnitCard[] = []
      for (const it of items) {
        const unit = String(it.unit || '').trim()
        if (!unit || seen.has(unit)) continue
        seen.add(unit)
        const st = it.status === 'done' ? 'Approved' : it.status === 'in_progress' ? 'In progress' : 'Not walked'
        cards.push({
          unit,
          bedrooms: 1,
          property: 'Thornbury at Chase Oaks',
          status: st,
          photo: null,
        })
        if (cards.length >= 8) break
      }
      if (cards.length) {
        setUnits(cards)
        setLive(true)
      }
    })()
    return () => { cancelled = true }
  }, [])

  function walk(u: UnitCard) {
    setWalkUnit({ unit: u.unit, bedrooms: u.bedrooms, property: u.property })
    nav('/walk')
  }

  return (
    <div className="min-h-full bg-ink text-[#F2F5FA] page-enter max-w-lg mx-auto flex flex-col">
      <header className="px-[22px] pt-[max(1rem,env(safe-area-inset-top))] pb-3">
        <div className="text-[11px] mono uppercase tracking-[0.16em] text-slate-dim">Field</div>
        <h1 className="text-[32px] font-bold tracking-[-0.035em] leading-[1.08] mt-1">Today</h1>
        <p className="text-[15px] text-slate mt-1">{units.length} units{live ? " · live" : ""}</p>
      </header>

      <main className="flex-1 px-[22px] pb-32 tab-safe">
        <div className="grid grid-cols-2 gap-3">
          {units.map((u, i) => (
            <button
              key={u.unit}
              type="button"
              onClick={() => walk(u)}
              className="press text-left rounded-[16px] bg-ink-raised border border-ink-line overflow-hidden"
            >
              <div className="aspect-[4/3] bg-ink-hover flex items-center justify-center">
                <span className="mono text-[28px] font-bold text-slate-dim">{u.unit}</span>
              </div>
              <div className="p-3">
                <div className="mono text-[15px] font-semibold">Unit {u.unit}</div>
                <div className="text-[12px] text-slate-dim mt-0.5 truncate">{u.property}</div>
                <div className="text-[12px] text-slate mt-0.5">{u.bedrooms} BR</div>
                <span className={`inline-block mt-2 rounded-full px-2 py-0.5 text-[10px] font-semibold ${STATUS_STYLE[u.status]}`}>
                  {u.status}
                </span>
                {i === 0 && (
                  <div className="mt-3">
                    <span className="inline-flex w-full justify-center rounded-full bg-gold text-ink text-[13px] font-bold py-2">
                      Walk unit
                    </span>
                  </div>
                )}
              </div>
            </button>
          ))}
        </div>
      </main>
    </div>
  )
}
