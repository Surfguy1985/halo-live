import { Link } from 'react-router-dom'
import { HaloLogo } from '@/components/HaloLogo'
import { PrimaryCTA } from '@/components/PrimaryCTA'

export default function Landing() {
  return (
    <div className="min-h-full bg-ink text-[#F2F5FA] page-enter flex flex-col max-w-lg mx-auto relative overflow-hidden">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,#16243F_0%,#080D1A_55%)]" />
      <div className="relative z-10 flex-1 flex flex-col px-[22px] pt-[max(3rem,env(safe-area-inset-top))] pb-10">
        <div className="flex items-center gap-2">
          <HaloLogo className="h-8 w-8" />
          <span className="text-[15px] font-semibold tracking-tight">Halo Live</span>
        </div>

        <div className="flex-1 flex flex-col justify-center">
          <p className="text-[11px] mono uppercase tracking-[0.2em] text-gold">Make-ready, live</p>
          <h1 className="mt-3 text-[36px] font-bold tracking-[-0.035em] leading-[1.08]">
            Order the unit.<br />Watch it finish.
          </h1>
          <p className="mt-4 text-[16px] text-slate leading-relaxed max-w-sm">
            Field builds the order. Property authorizes with a PO. Crews accept like a ride.
            Everyone tracks the same chain — including the hours the unit is closed while it cures.
          </p>
          <ul className="mt-8 space-y-3 text-[14px] text-slate">
            <li className="flex gap-2"><span className="text-gold">●</span> Menu of services with cure cost visible before you add</li>
            <li className="flex gap-2"><span className="text-gold">●</span> PO checkout that feels like payment</li>
            <li className="flex gap-2"><span className="text-gold">●</span> Multi-day ETA stack — chemistry, not a spinner</li>
          </ul>
        </div>

        <Link to="/enter" className="block">
          <PrimaryCTA>Enter Halo Live</PrimaryCTA>
        </Link>
        <p className="mt-3 text-center text-[12px] text-slate-dim">
          Field · Property · Crew · Dispatch — one live order
        </p>
      </div>
    </div>
  )
}
