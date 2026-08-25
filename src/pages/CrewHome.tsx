/**
 * Crew home — closed units during cure + open jobs
 */
import { Link } from 'react-router-dom'
import { MapPin, Bell } from 'lucide-react'
import { PrimaryCTA } from '@/components/PrimaryCTA'

export default function CrewHome() {
  return (
    <div className="min-h-full bg-ink text-[#F2F5FA] page-enter max-w-lg mx-auto flex flex-col">
      <header className="px-[22px] pt-[max(1rem,env(safe-area-inset-top))] pb-4 flex items-center justify-between">
        <div>
          <div className="text-[11px] mono uppercase tracking-[0.16em] text-slate-dim">Crew</div>
          <h1 className="text-[28px] font-bold tracking-[-0.03em]">Jose M</h1>
        </div>
        <Link to="/crew/ping" className="press relative h-11 w-11 rounded-full bg-ink-raised border border-ink-line grid place-items-center">
          <Bell className="h-5 w-5 text-gold" />
          <span className="absolute top-2 right-2 h-2 w-2 rounded-full bg-live" />
        </Link>
      </header>

      <main className="flex-1 px-[22px] space-y-4 pb-24">
        {/* Cure closed unit — never walk in */}
        <div className="rounded-[16px] border border-warn/40 bg-warn/10 p-4">
          <div className="text-[11px] mono uppercase tracking-[0.16em] text-warn">Unit closed</div>
          <div className="mt-1 text-[16px] font-semibold">Unit 1713 · closed until 7:40 AM Tue</div>
          <div className="mt-1 text-[13px] text-slate">Tub curing — do not enter. Ruins the finish and costs another window.</div>
        </div>

        <div className="rounded-[16px] bg-ink-raised border border-ink-line p-4">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div className="mono text-[15px] font-semibold text-gold">$230.00</div>
              <div className="text-[17px] font-semibold mt-1">Wall Prep &amp; Paint (1 BR)</div>
              <div className="text-[13px] text-slate mt-1 flex items-center gap-1">
                <MapPin className="h-3.5 w-3.5" /> Unit 1713 · after cure
              </div>
            </div>
          </div>
          <div className="mt-4">
            <Link to="/crew/ping">
              <PrimaryCTA>View ping</PrimaryCTA>
            </Link>
          </div>
        </div>

        <p className="text-[13px] text-slate-dim text-center pt-4">
          You only get pings for units that are open. Cure frees you for other sites.
        </p>
      </main>
    </div>
  )
}
