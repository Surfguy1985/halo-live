/**
 * C1 · Crew ping — Uber Driver accept, data from dispatch queue
 */
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { PrimaryCTA } from '@/components/PrimaryCTA'
import { formatMoney } from '@/lib/catalog'
import { loadCrewPing, clearCrewPing } from '@/lib/orderBus'

const TOTAL_SEC = 20

export default function CrewPing() {
  const nav = useNavigate()
  const ping = loadCrewPing()
  const [left, setLeft] = useState(TOTAL_SEC)
  const [accepted, setAccepted] = useState(false)

  const price = ping?.priceCents ?? 23000
  const service = ping?.serviceName ?? 'Wall Prep & Paint (1 BR)'
  const unit = ping?.unit ?? '1713'
  const property = ping?.property ?? 'Thornbury at Chase Oaks'

  useEffect(() => {
    if (accepted) return
    if (left <= 0) {
      clearCrewPing()
      nav('/crew')
      return
    }
    const t = setTimeout(() => setLeft((s) => s - 1), 1000)
    return () => clearTimeout(t)
  }, [left, accepted, nav])

  const pct = left / TOTAL_SEC

  if (accepted) {
    return (
      <div className="min-h-full bg-ink text-[#F2F5FA] page-enter max-w-lg mx-auto flex flex-col items-center justify-center px-[22px] text-center">
        <div className="h-16 w-16 rounded-full bg-ok/20 grid place-items-center mb-6">
          <span className="text-ok text-2xl font-bold">✓</span>
        </div>
        <h1 className="text-[28px] font-bold tracking-[-0.03em]">You&apos;re on it</h1>
        <p className="mt-3 text-[15px] text-slate max-w-sm">
          {service} · Unit {unit}. Navigate when you&apos;re ready.
        </p>
        <div className="mt-10 w-full space-y-3">
          <PrimaryCTA onClick={() => nav('/crew/job')}>Open work order</PrimaryCTA>
          <button type="button" onClick={() => nav('/crew')} className="press w-full py-3 text-[15px] text-slate">
            Back to board
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-full bg-ink text-[#F2F5FA] page-enter max-w-lg mx-auto flex flex-col relative overflow-hidden">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,#16243F_0%,#080D1A_70%)]" />
      <div className="relative z-10 flex-1 flex flex-col px-[22px] pt-[max(2rem,env(safe-area-inset-top))] pb-8">
        <div className="text-center text-[13px] text-slate">
          {ping ? `Ping for ${ping.crewName}` : 'New work'} · expires in
        </div>

        <div className="flex justify-center my-8">
          <div className="relative h-28 w-28">
            <svg className="h-28 w-28 -rotate-90" viewBox="0 0 100 100">
              <circle cx="50" cy="50" r="44" fill="none" stroke="#1E2E4C" strokeWidth="6" />
              <circle
                cx="50" cy="50" r="44" fill="none" stroke="#E3B85C" strokeWidth="6"
                strokeLinecap="round"
                strokeDasharray={`${pct * 276.5} 276.5`}
              />
            </svg>
            <div className="absolute inset-0 grid place-items-center">
              <span className="mono text-[28px] font-bold">{left}</span>
            </div>
          </div>
        </div>

        <div className="text-center">
          <div className="mono text-[40px] font-bold tracking-[-0.03em] text-gold leading-none">
            {formatMoney(price)}
          </div>
          <h1 className="mt-4 text-[25px] font-bold tracking-[-0.03em]">{service}</h1>
          <p className="mt-2 text-[15px] text-slate">
            Unit <span className="mono font-semibold text-[#F2F5FA]">{unit}</span> · {property}
          </p>
        </div>

        <div className="mt-auto space-y-3 pt-8">
          <PrimaryCTA
            onClick={() => {
              setAccepted(true)
            }}
          >
            Accept
          </PrimaryCTA>
          <button
            type="button"
            onClick={() => {
              clearCrewPing()
              nav('/crew')
            }}
            className="press w-full rounded-full border border-ink-line py-[15px] text-[16px] font-semibold text-slate"
          >
            Decline
          </button>
        </div>
      </div>
    </div>
  )
}
