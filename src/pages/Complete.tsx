/**
 * Walk report — scoped complete + NOT IN SCOPE not billed
 */
import { Link } from 'react-router-dom'
import { loadSharedOrder } from '@/lib/orderBus'
import { loadClientSetup } from '@/lib/onboarding'
import { formatMoney } from '@/lib/catalog'
import { PrimaryCTA } from '@/components/PrimaryCTA'

export default function Complete() {
  const order = loadSharedOrder()
  const setup = loadClientSetup()
  const unit = order?.unit || setup?.unitDemo || '2412'
  const property = order?.property || setup?.propertyName || 'Willow Creek Apartments'
  const lines = order?.lines || []
  const total = order?.totalCents || 418000
  const po = order?.po || '4471'
  const date = new Date().toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' })

  return (
    <div className="min-h-full theme-light bg-white text-ink page-enter max-w-lg mx-auto pb-28">
      <header className="px-[22px] pt-[max(1.25rem,env(safe-area-inset-top))] pb-2">
        <div className="text-[11px] font-semibold tracking-[0.16em] uppercase text-text-muted">
          HALO · Make-ready report
        </div>
        <h1 className="mt-3 text-[32px] font-bold tracking-[-0.03em] leading-tight">
          Unit {unit} is ready.
        </h1>
        <p className="mt-2 text-[14px] text-text-muted">
          {property} · Completed {date}
        </p>

        {/* Progress rail */}
        <div className="mt-6">
          <div className="h-1.5 rounded-full bg-[#E8E8E4] overflow-hidden">
            <div className="h-full w-full bg-[#00C853] rounded-full" />
          </div>
          <div className="mt-2 flex justify-between text-[12px] font-medium text-[#00C853]">
            <span>Arrived</span>
            <span>Work done</span>
            <span>QC passed</span>
          </div>
        </div>
      </header>

      <main className="px-[22px] py-6 space-y-4">
        <div className="rounded-[16px] bg-[#F7F7F5] p-5">
          <div className="text-[12px] font-semibold tracking-[0.12em] uppercase text-[#00C853]">
            {lines.length || 6} scoped items completed
          </div>
          <ul className="mt-3 space-y-2">
            {(lines.length
              ? lines.map((l) => l.name)
              : [
                  'Full interior paint — walls, ceilings, trim',
                  'Carpet replaced — both bedrooms',
                  'Appliance clean + detail — kitchen',
                  'Blinds replaced — 4 windows',
                  'Tub reglaze — primary bath',
                  'Final clean + punch walk',
                ]
            ).map((name) => (
              <li key={name} className="text-[15px] text-ink leading-snug">
                {name}
              </li>
            ))}
          </ul>

          <div className="mt-5 pt-4 border-t border-black/5">
            <div className="text-[11px] font-bold tracking-[0.1em] uppercase text-[#E67E22]">
              Not in scope · Not performed · Not billed
            </div>
            <ul className="mt-2 space-y-1.5 text-[14px] text-text-muted">
              <li>Balcony railing repair — not on approved scope</li>
              <li>HVAC filter service — handled by on-site staff</li>
            </ul>
          </div>
        </div>

        <div className="flex justify-between items-end px-1 pt-2">
          <div className="text-[13px] text-text-muted">
            PO #{po} · {lines.length || 6} line items
          </div>
          <div className="mono text-[20px] font-bold">{formatMoney(total)}</div>
        </div>
      </main>

      <div className="fixed bottom-0 inset-x-0 max-w-lg mx-auto p-4 pb-[max(1rem,env(safe-area-inset-bottom))] bg-white border-t border-line">
        <PrimaryCTA onClick={() => {}}>Share report</PrimaryCTA>
        <Link to="/live" className="block text-center text-[13px] text-text-muted mt-2 py-1">
          Back to live map
        </Link>
      </div>
    </div>
  )
}
