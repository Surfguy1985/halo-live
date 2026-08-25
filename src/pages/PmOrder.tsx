/**
 * App B · Property Manager (light)
 * Incoming → edit → PO authorize → authorized
 */
import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ArrowLeft, Camera, MessageCircle } from 'lucide-react'
import { PrimaryCTA } from '@/components/PrimaryCTA'
import { formatMoney } from '@/lib/catalog'
import { cn } from '@/lib/cn'
import { loadSharedOrder, authorizeSharedOrder, patchSharedOrder } from '@/lib/orderBus'
import { fetchJson } from '@/lib/api'

type Phase = 'incoming' | 'edit' | 'po' | 'done'

const FALLBACK_LINES = [
  { id: '1', name: 'Wall Prep & Paint (1 BR)', priceCents: 23000, checked: true },
  { id: '2', name: 'Vacant Unit Clean (1 BR)', priceCents: 15000, checked: true },
  { id: '3', name: 'Carpet Clean (1 BR)', priceCents: 9500, checked: true },
  { id: '4', name: 'Doors & Trim', priceCents: 14000, checked: true },
]

export default function PmOrder() {
  const nav = useNavigate()
  const shared = loadSharedOrder()
  const initial = shared && shared.lines.length
    ? shared.lines.map((l, i) => ({
        id: l.familyId || String(i),
        name: l.name,
        priceCents: l.priceCents * l.qty,
        checked: true,
      }))
    : FALLBACK_LINES
  const [phase, setPhase] = useState<Phase>('incoming')
  const [lines, setLines] = useState(initial)
  const [po, setPo] = useState(shared?.po || '')
  const unitNo = shared?.unit || '1713'
  const propName = shared?.property || 'Thornbury at Chase Oaks'

  const total = lines.filter((l) => l.checked).reduce((s, l) => s + l.priceCents, 0)
  const count = lines.filter((l) => l.checked).length

  if (phase === 'done') {
    return (
      <div className="min-h-full theme-light page-enter max-w-lg mx-auto flex flex-col">
        <div className="flex-1 flex flex-col items-center justify-center px-[22px] text-center bg-gradient-to-b from-[#E8F8EE] to-paper">
          <div className="h-16 w-16 rounded-full bg-ok grid place-items-center mb-6">
            <span className="text-white text-2xl font-bold">✓</span>
          </div>
          <h1 className="text-[28px] font-bold tracking-[-0.03em] text-ink">Work authorized</h1>
          <p className="mt-3 text-[15px] text-text-muted max-w-sm">
            <span className="mono font-semibold text-ink">{po || 'PO-88231'}</span> recorded. Halo is
            dispatching crews now.
          </p>
          <div className="mt-8 flex items-center gap-2 text-[11px] mono uppercase tracking-wider text-text-muted">
            {['Authorized', 'Dispatched', 'On site', 'Complete'].map((s, i) => (
              <span key={s} className="flex items-center gap-2">
                <span className={cn('h-2 w-2 rounded-full', i === 0 ? 'bg-ok' : 'bg-line')} />
                {s}
                {i < 3 && <span className="text-line">—</span>}
              </span>
            ))}
          </div>
          <div className="mt-10 w-full max-w-sm">
            <PrimaryCTA onClick={() => nav('/track')}>Track the work</PrimaryCTA>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-full theme-light page-enter max-w-lg mx-auto flex flex-col bg-paper text-ink">
      <header className="flex h-14 items-center gap-3 px-4 bg-white border-b border-line">
        <button type="button" onClick={() => (phase === 'incoming' ? nav('/live') : setPhase(phase === 'po' ? 'edit' : 'incoming'))} className="press h-10 w-10 rounded-full grid place-items-center hover:bg-line/50">
          <ArrowLeft className="h-5 w-5" />
        </button>
        <div className="flex-1">
          <div className="text-[17px] font-semibold">
            {phase === 'incoming' && 'New work order'}
            {phase === 'edit' && 'Edit the order'}
            {phase === 'po' && 'Authorize the work'}
          </div>
        </div>
        {phase === 'incoming' && (
          <span className="rounded-full bg-warn/15 text-warn text-[11px] font-semibold px-2.5 py-1">
            Needs your approval
          </span>
        )}
      </header>

      <main className="flex-1 px-[22px] py-5 pb-32 space-y-5">
        {/* Unit card */}
        <div className="rounded-[16px] bg-white border border-line overflow-hidden shadow-sm">
          <div className="aspect-[16/9] bg-line/40 flex items-center justify-center">
            <span className="mono text-[32px] font-bold text-text-muted/40">{unitNo}</span>
          </div>
          <div className="p-4">
            <div className="mono text-[18px] font-bold">{`Unit ${unitNo}`}</div>
            <div className="text-[13px] text-text-muted mt-0.5">{`${propName} · from Halo field`}</div>
          </div>
        </div>

        {/* Lines */}
        <div className="rounded-[16px] bg-white border border-line divide-y divide-line">
          {lines.map((l) => (
            <div key={l.id} className="flex items-center gap-3 px-4 py-3.5">
              {(phase === 'edit' || phase === 'incoming') && (
                <input
                  type="checkbox"
                  checked={l.checked}
                  onChange={() =>
                    setLines((prev) =>
                      prev.map((x) => (x.id === l.id ? { ...x, checked: !x.checked } : x)),
                    )
                  }
                  className="h-5 w-5 rounded accent-[#A8791F]"
                />
              )}
              <div className="flex-1 min-w-0">
                <div className={cn('text-[15px] font-medium', !l.checked && 'line-through text-text-muted')}>
                  {l.name}
                </div>
              </div>
              <div className="mono text-[15px] font-semibold">{formatMoney(l.priceCents)}</div>
            </div>
          ))}
        </div>

        <button type="button" className="flex items-center gap-2 text-[14px] font-medium text-gold-deep">
          <Camera className="h-4 w-4" /> 11 before photos
        </button>

        {phase === 'po' && (
          <>
            <div>
              <div className="text-[13px] font-semibold text-text-muted mb-2">Payment method</div>
              <div className="rounded-[16px] bg-white border border-line p-4">
                <div className="flex items-center gap-3 mb-3">
                  <div className="h-10 w-10 rounded-[10px] bg-ink text-gold grid place-items-center text-[12px] font-bold">
                    PO
                  </div>
                  <div>
                    <div className="text-[15px] font-semibold">Purchase order</div>
                    <div className="text-[12px] text-text-muted">Authorizes work and releases payment on verify</div>
                  </div>
                </div>
                <input
                  value={po}
                  onChange={(e) => setPo(e.target.value)}
                  placeholder="PO-00000"
                  className="mono w-full rounded-[10px] border border-line bg-paper px-4 py-3 text-[16px] outline-none focus:border-gold-deep"
                />
              </div>
            </div>
            <div className="rounded-[16px] bg-white border border-line p-4 space-y-2 text-[14px]">
              <div className="flex justify-between">
                <span className="text-text-muted">Services</span>
                <span className="mono font-medium">{formatMoney(total)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-muted">Found outside PO</span>
                <span className="mono font-medium text-text-muted">$0.00 — not billed</span>
              </div>
              <div className="flex justify-between pt-2 border-t border-line">
                <span className="font-semibold">Total authorized</span>
                <span className="mono text-[18px] font-bold">{formatMoney(total)}</span>
              </div>
            </div>
          </>
        )}

        {phase !== 'po' && (
          <div className="flex justify-between items-center">
            <span className="text-[15px] text-text-muted">{count} services</span>
            <span className="mono text-[22px] font-bold">{formatMoney(total)}</span>
          </div>
        )}
      </main>

      <div className="fixed bottom-0 inset-x-0 max-w-lg mx-auto p-4 pb-[max(1rem,env(safe-area-inset-bottom))] bg-white border-t border-line space-y-2">
        {phase === 'incoming' && (
          <>
            <PrimaryCTA onClick={() => setPhase('edit')}>Review & approve</PrimaryCTA>
            <button type="button" className="press w-full py-3 text-[15px] font-medium text-text-muted flex items-center justify-center gap-2">
              <MessageCircle className="h-4 w-4" /> Message Halo
            </button>
          </>
        )}
        {phase === 'edit' && (
          <PrimaryCTA onClick={() => setPhase('po')}>Looks good — continue</PrimaryCTA>
        )}
        {phase === 'po' && (
          <PrimaryCTA
            disabled={!po.trim()}
            onClick={async () => {
              const o = authorizeSharedOrder(po.trim())
              if (o?.haloJobId) {
                await fetchJson(`/api/jobs/${o.haloJobId}/client-po`, {
                  method: 'POST',
                  body: JSON.stringify({ poNumber: po.trim() }),
                })
                patchSharedOrder({ status: 'authorized', po: po.trim() })
              }
              setPhase('done')
            }}
          >
            Authorize {formatMoney(total)}
          </PrimaryCTA>
        )}
      </div>
    </div>
  )
}
