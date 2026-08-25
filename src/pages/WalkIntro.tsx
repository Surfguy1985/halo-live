import { Link, useNavigate } from 'react-router-dom'
import { ArrowLeft } from 'lucide-react'
import { getWalkUnit } from '@/lib/catalog'
import { PrimaryCTA } from '@/components/PrimaryCTA'

export default function WalkIntro() {
  const nav = useNavigate()
  const unit = getWalkUnit() || { unit: '1713', bedrooms: 1, property: 'Thornbury at Chase Oaks' }

  return (
    <div className="min-h-full bg-ink text-[#F2F5FA] page-enter max-w-lg mx-auto flex flex-col">
      <header className="flex h-14 items-center justify-between px-4">
        <button type="button" onClick={() => nav('/units')} className="press h-10 w-10 rounded-full grid place-items-center hover:bg-ink-hover">
          <ArrowLeft className="h-5 w-5" />
        </button>
        <span className="text-[13px] text-slate">Help</span>
      </header>

      <div className="flex-1 px-[22px] pb-8 flex flex-col">
        <div className="flex-1 flex flex-col items-center text-center pt-6">
          <div className="w-full max-w-xs aspect-square rounded-[32px] bg-ink-raised border border-ink-line flex items-center justify-center mb-8">
            <div className="w-3/4 h-3/4 rounded-2xl border-2 border-dashed border-slate-dim/40 relative">
              <div className="absolute inset-3 rounded-lg bg-gold/20 border border-gold/40" />
              <span className="absolute bottom-2 left-0 right-0 mono text-[12px] text-slate-dim">Floor plan</span>
            </div>
          </div>
          <h1 className="text-[28px] font-bold tracking-[-0.03em]">Walk unit {unit.unit}</h1>
          <p className="mt-3 text-[15px] text-slate leading-relaxed max-w-sm">
            Add every service this unit needs. The property manager approves the whole order at once, so nothing gets added later without a change order.
          </p>
          <button type="button" className="mt-4 text-[14px] font-medium text-gold">
            View the Thornbury price list
          </button>
        </div>
        <PrimaryCTA onClick={() => nav('/order')}>Start the walk</PrimaryCTA>
      </div>
    </div>
  )
}
