import { Link, useNavigate } from 'react-router-dom'
import { ArrowLeft } from 'lucide-react'
import { PrimaryCTA } from '@/components/PrimaryCTA'

export default function CrewJob() {
  const nav = useNavigate()
  return (
    <div className="min-h-full bg-ink text-[#F2F5FA] page-enter max-w-lg mx-auto flex flex-col">
      <header className="flex h-14 items-center gap-3 px-4 border-b border-ink-line">
        <button type="button" onClick={() => nav('/crew')} className="press h-10 w-10 rounded-full grid place-items-center">
          <ArrowLeft className="h-5 w-5" />
        </button>
        <div className="text-[17px] font-semibold">Work order</div>
      </header>
      <main className="flex-1 px-[22px] py-5 space-y-5 pb-28">
        <div>
          <div className="mono text-[13px] text-slate-dim">Unit 1713 · Thornbury</div>
          <h1 className="text-[25px] font-bold tracking-[-0.03em] mt-1">Wall Prep &amp; Paint</h1>
          <p className="text-[14px] text-slate mt-2">Rooms: Whole unit · 1 BR rate</p>
        </div>
        <div className="rounded-[16px] bg-ink-raised border border-ink-line p-4">
          <div className="text-[11px] mono uppercase tracking-[0.16em] text-slate-dim">Field note</div>
          <p className="mt-2 text-[14px] text-slate leading-relaxed">
            Match before angles in the living room. Touch up only on the south wall patch — full cut-in elsewhere.
          </p>
        </div>
        <div>
          <div className="text-[14px] font-semibold mb-2">Before photos · reference</div>
          <div className="flex gap-2 overflow-x-auto no-scrollbar">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-24 w-24 shrink-0 rounded-[10px] bg-ink-hover border border-ink-line" />
            ))}
          </div>
          <p className="text-[12px] text-slate-dim mt-2">This is what it looked like at 8:12 AM</p>
        </div>
        <div className="text-[13px] text-slate">
          Sequence: 2nd of 4 · Marco resurfaces after you if tub is already cured.
        </div>
      </main>
      <div className="fixed bottom-0 inset-x-0 max-w-lg mx-auto p-4 pb-[max(1rem,env(safe-area-inset-bottom))] bg-ink border-t border-ink-line space-y-2">
        <PrimaryCTA onClick={() => nav('/field')}>Start work · after photos</PrimaryCTA>
        <Link to="/crew" className="block text-center text-[14px] text-slate py-2">Back</Link>
      </div>
    </div>
  )
}
