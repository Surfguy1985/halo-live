/**
 * New-client onboarding — splash beats + setup + optional demo
 */
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { HaloRing, HaloWordmark, OrbitPins, PhotoStack } from '@/components/HaloMark'
import { PrimaryCTA } from '@/components/PrimaryCTA'
import { setRoleInStorage, type Role } from '@/lib/api'
import { saveClientSetup, markOnboardingDone } from '@/lib/onboarding'
import { roleHome } from '@/components/AppTabs'
import { publishOrderFromCart } from '@/lib/orderBus'
import { SERVICE_FAMILIES, type CartLine } from '@/lib/catalog'
import { cn } from '@/lib/cn'

const STEPS = ['welcome', 'how', 'photos', 'role', 'property', 'demo'] as const
type Step = (typeof STEPS)[number]

export default function Onboard() {
  const nav = useNavigate()
  const [step, setStep] = useState<Step>('welcome')
  const [role, setRole] = useState<Role>('pulse')
  const [property, setProperty] = useState('Thornbury at Chase Oaks')
  const [unit, setUnit] = useState('1713')
  const idx = STEPS.indexOf(step)

  function next() {
    if (idx < STEPS.length - 1) setStep(STEPS[idx + 1])
  }
  function back() {
    if (idx > 0) setStep(STEPS[idx - 1])
  }

  function finish(runDemo: boolean) {
    setRoleInStorage(role)
    saveClientSetup({ propertyName: property.trim() || 'My Property', unitDemo: unit.trim() || '100' })
    if (runDemo) {
      // Seed a sample order so Approve / Track / Complete feel alive
      const paint = SERVICE_FAMILIES.find((f) => f.id === 'paint')
      const clean = SERVICE_FAMILIES.find((f) => f.id === 'clean')
      const lines: CartLine[] = []
      if (paint) {
        lines.push({
          familyId: paint.id,
          name: paint.name,
          variantId: paint.variants[0].id,
          variantLabel: paint.variants[0].label,
          priceCents: paint.variants[0].priceCents,
          durationHours: paint.variants[0].durationHours,
          cureHours: paint.variants[0].cureHours || 0,
          qty: 1,
        })
      }
      if (clean) {
        lines.push({
          familyId: clean.id,
          name: clean.name,
          variantId: clean.variants[0].id,
          variantLabel: clean.variants[0].label,
          priceCents: clean.variants[0].priceCents,
          durationHours: clean.variants[0].durationHours,
          cureHours: 0,
          qty: 1,
        })
      }
      if (lines.length) publishOrderFromCart(lines, 'sent')
      try {
        localStorage.setItem('halo-live-walk-unit', JSON.stringify({ unit: unit || '1713', bedrooms: 1, property }))
      } catch { /* ignore */ }
    }
    markOnboardingDone()
    nav(roleHome(role), { replace: true })
  }

  return (
    <div className="min-h-[100dvh] bg-ink text-[#F2F5FA] max-w-lg mx-auto flex flex-col page-enter">
      {/* progress */}
      <div className="px-[22px] pt-[max(1rem,env(safe-area-inset-top))] pb-2 flex items-center gap-2">
        {STEPS.map((s, i) => (
          <div
            key={s}
            className={cn('h-1 flex-1 rounded-full', i <= idx ? 'bg-gold' : 'bg-ink-line')}
          />
        ))}
      </div>

      <main className="flex-1 flex flex-col px-[22px] py-6">
        {step === 'welcome' && (
          <div className="flex-1 flex flex-col items-center text-center justify-center gap-6">
            <HaloRing className="h-24 w-24" glow />
            <HaloWordmark className="text-white" size="lg" />
            <div>
              <h1 className="text-[28px] font-bold tracking-[-0.03em]">Welcome to Halo</h1>
              <p className="mt-3 text-[15px] text-slate leading-relaxed max-w-sm mx-auto">
                Apartment make-ready as one live order. Field builds it. Property authorizes with a PO. Crews deliver. Everyone watches the same list.
              </p>
            </div>
          </div>
        )}

        {step === 'how' && (
          <div className="flex-1 flex flex-col items-center text-center justify-center gap-6">
            <OrbitPins className="h-44 w-44" />
            <div>
              <h1 className="text-[26px] font-bold tracking-[-0.03em]">Order → authorize → track</h1>
              <ul className="mt-4 text-left text-[14px] text-slate space-y-3 max-w-sm mx-auto">
                <li><span className="text-gold font-semibold">1.</span> Field walks the unit and adds services like a menu.</li>
                <li><span className="text-gold font-semibold">2.</span> Property reviews and enters a <span className="text-[#F2F5FA]">PO</span> — that is payment.</li>
                <li><span className="text-gold font-semibold">3.</span> Live map + ETA stack show crew and cure windows.</li>
              </ul>
            </div>
          </div>
        )}

        {step === 'photos' && (
          <div className="flex-1 flex flex-col items-center text-center justify-center gap-6">
            <div className="rounded-[24px] bg-[#F4F4F0] p-6">
              <PhotoStack className="h-40 w-40" />
            </div>
            <div>
              <h1 className="text-[26px] font-bold tracking-[-0.03em]">Photo proof, not paperwork</h1>
              <p className="mt-3 text-[15px] text-slate max-w-sm mx-auto leading-relaxed">
                Guided check-in captures before and after. Out-of-scope work is documented as evidence — never billed by accident.
              </p>
            </div>
          </div>
        )}

        {step === 'role' && (
          <div className="flex-1 flex flex-col">
            <h1 className="text-[26px] font-bold tracking-[-0.03em]">Who are you?</h1>
            <p className="mt-2 text-[14px] text-slate">You can switch later from the home screen.</p>
            <div className="mt-8 space-y-3">
              {(
                [
                  { id: 'pulse' as Role, title: 'Property manager', body: 'Approve orders with a PO · track ETA' },
                  { id: 'vendor' as Role, title: 'Field / vendor', body: 'Walk units · build the order · dispatch crews' },
                  { id: 'portfolio' as Role, title: 'Portfolio / corporate', body: 'Live map across properties' },
                ] as const
              ).map((r) => (
                <button
                  key={r.id}
                  type="button"
                  onClick={() => setRole(r.id)}
                  className={cn(
                    'press w-full text-left rounded-[16px] border p-4',
                    role === r.id ? 'border-gold bg-gold/10' : 'border-ink-line bg-ink-raised',
                  )}
                >
                  <div className="text-[16px] font-semibold">{r.title}</div>
                  <div className="text-[13px] text-slate mt-0.5">{r.body}</div>
                </button>
              ))}
            </div>
          </div>
        )}

        {step === 'property' && (
          <div className="flex-1 flex flex-col">
            <h1 className="text-[26px] font-bold tracking-[-0.03em]">Your property</h1>
            <p className="mt-2 text-[14px] text-slate">Used for demo labels and walk units. Live data still comes from Halo when connected.</p>
            <label className="mt-8 block text-[12px] mono uppercase tracking-wide text-slate-dim">Property name</label>
            <input
              value={property}
              onChange={(e) => setProperty(e.target.value)}
              className="mt-2 w-full rounded-[14px] bg-ink-raised border border-ink-line px-4 py-3.5 text-[16px] outline-none focus:border-gold"
              placeholder="Thornbury at Chase Oaks"
            />
            <label className="mt-5 block text-[12px] mono uppercase tracking-wide text-slate-dim">Demo unit</label>
            <input
              value={unit}
              onChange={(e) => setUnit(e.target.value)}
              className="mt-2 w-full rounded-[14px] bg-ink-raised border border-ink-line px-4 py-3.5 text-[16px] outline-none focus:border-gold"
              placeholder="1713"
            />
          </div>
        )}

        {step === 'demo' && (
          <div className="flex-1 flex flex-col items-center text-center justify-center gap-4">
            <div className="text-[11px] mono uppercase tracking-[0.16em] text-live">You&apos;re set</div>
            <h1 className="text-[28px] font-bold tracking-[-0.03em]">Try a sample order?</h1>
            <p className="text-[15px] text-slate max-w-sm">
              We&apos;ll seed a small make-ready for Unit {unit || '1713'} so Approve, Track, and Dispatch already have something to show.
            </p>
          </div>
        )}
      </main>

      <div className="px-[22px] pb-[max(1.25rem,env(safe-area-inset-bottom))] space-y-2">
        {step === 'demo' ? (
          <>
            <PrimaryCTA onClick={() => finish(true)}>Run demo · enter app</PrimaryCTA>
            <button type="button" onClick={() => finish(false)} className="press w-full py-3 text-[14px] text-slate">
              Skip demo · enter empty
            </button>
          </>
        ) : (
          <>
            <PrimaryCTA onClick={next}>{step === 'welcome' ? 'Get started' : 'Continue'}</PrimaryCTA>
            {idx > 0 && (
              <button type="button" onClick={back} className="press w-full py-2 text-[14px] text-slate-dim">
                Back
              </button>
            )}
            <button
              type="button"
              onClick={() => finish(false)}
              className="press w-full py-2 text-[12px] text-slate-dim"
            >
              Skip setup
            </button>
          </>
        )}
      </div>
    </div>
  )
}
