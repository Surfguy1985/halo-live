/**
 * A6 · Review order — cart + schedule + gap check + send
 */
import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { ArrowLeft, Trash2 } from 'lucide-react'
import {
  loadCart, saveCart, clearCart, cartTotalCents, formatMoney,
  projectSchedule, sequenceGaps, getWalkUnit, resolveVariant, SERVICE_FAMILIES,
  type CartLine,
} from '@/lib/catalog'
import { createWorkOrder, submitLiveOrder, resolvePropertyId } from '@/lib/api'
import { PrimaryCTA } from '@/components/PrimaryCTA'
import { publishOrderFromCart } from '@/lib/orderBus'

export default function Checkout() {
  const nav = useNavigate()
  const unit = getWalkUnit() || { unit: '1713', bedrooms: 1, property: 'Thornbury at Chase Oaks' }
  const [cart, setCart] = useState<CartLine[]>(() => loadCart())
  const [busy, setBusy] = useState(false)
  const [sent, setSent] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [skipGap, setSkipGap] = useState(false)

  const total = cartTotalCents(cart)
  const schedule = projectSchedule(cart)
  const gaps = skipGap ? [] : sequenceGaps(cart)

  function update(next: CartLine[]) {
    setCart(next)
    saveCart(next)
  }

  function remove(id: string) {
    update(cart.filter((l) => l.familyId !== id))
  }

  function addFamily(id: string) {
    const fam = SERVICE_FAMILIES.find((f) => f.id === id)
    if (!fam) return
    const v = resolveVariant(fam, unit.bedrooms)
    update([
      ...cart,
      {
        familyId: id,
        name: fam.name,
        variantKey: v.key,
        priceCents: v.priceCents,
        durationHours: v.durationHours,
        cureHours: v.cureHours,
        qty: 1,
      },
    ])
    setSkipGap(true)
  }

  async function send() {
    if (!cart.length) return
    setBusy(true)
    setError(null)
    const services = cart.map((l) => l.name)
    const desc = services.join(' · ')
    const { id: propertyId } = await resolvePropertyId()
    let haloJobId: string | undefined
    let jobNo: string | undefined
    if (propertyId) {
      const live = await submitLiveOrder({
        propertyId,
        unitNo: unit.unit,
        description: desc,
        price: total / 100,
      })
      if (live.ok) {
        haloJobId = live.order.id
        jobNo = live.order.jobNo
      } else {
        // Fallback quick create
        const res = await createWorkOrder({ unit: unit.unit, services, notes: schedule.finishLabel })
        if (res.error) {
          setBusy(false)
          setError(res.error || live.error)
          return
        }
        haloJobId = res.id
      }
    } else {
      const res = await createWorkOrder({ unit: unit.unit, services, notes: schedule.finishLabel })
      if (res.error) {
        // Still allow local demo flow offline
        console.warn(res.error)
      } else {
        haloJobId = res.id
      }
    }
    setBusy(false)
    publishOrderFromCart(cart, 'sent', { haloJobId, jobNo })
    clearCart()
    setSent(true)
  }

  if (sent) {
    return (
      <div className="min-h-full bg-ink text-[#F2F5FA] page-enter max-w-lg mx-auto flex flex-col items-center justify-center px-[22px] text-center">
        <div className="h-16 w-16 rounded-full bg-ok/20 flex items-center justify-center mb-6">
          <span className="text-ok text-3xl">✓</span>
        </div>
        <h1 className="text-[28px] font-bold tracking-[-0.03em]">Order sent</h1>
        <p className="mt-3 text-[15px] text-slate max-w-sm">
          It&apos;s on the property manager&apos;s desk. She enters a PO to authorize — same order, same list.
        </p>
        <div className="mt-8 w-full">
          <PrimaryCTA onClick={() => nav('/live')}>Back to live</PrimaryCTA>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-full bg-ink text-[#F2F5FA] page-enter max-w-lg mx-auto flex flex-col">
      <header className="flex h-14 items-center gap-3 px-4 border-b border-ink-line">
        <button type="button" onClick={() => nav('/order')} className="press h-10 w-10 rounded-full grid place-items-center hover:bg-ink-hover">
          <ArrowLeft className="h-5 w-5" />
        </button>
        <div className="flex-1">
          <div className="text-[17px] font-semibold">Review order</div>
          <div className="mono text-[12px] text-slate-dim">Unit {unit.unit}</div>
        </div>
      </header>

      <main className="flex-1 px-[22px] py-4 pb-36 space-y-4">
        {cart.length === 0 && (
          <p className="text-center text-slate py-16">Cart is empty. Add services from the menu.</p>
        )}

        {cart.map((l) => (
          <div key={l.familyId} className="flex items-start gap-3 py-3 border-b border-ink-line/50">
            <div className="flex-1 min-w-0">
              <div className="text-[15px] font-semibold">{l.name}</div>
              <div className="mono text-[12px] text-slate-dim mt-0.5">
                {l.variantKey} · qty {l.qty}
                {l.cureHours > 0 ? ` · +${l.cureHours}h cure` : ''}
              </div>
            </div>
            <div className="mono text-[15px] font-semibold">{formatMoney(l.priceCents * l.qty)}</div>
            <button type="button" onClick={() => remove(l.familyId)} className="press p-1 text-slate-dim hover:text-danger">
              <Trash2 className="h-4 w-4" />
            </button>
          </div>
        ))}

        {/* Schedule block */}
        {cart.length > 0 && (
          <div className="rounded-[16px] bg-ink-raised border border-ink-line p-4">
            <div className="text-[11px] mono uppercase tracking-[0.16em] text-slate-dim">Schedule</div>
            <div className="mt-2 mono text-[15px] font-semibold">
              Complete · {schedule.finishLabel}
            </div>
            <div className="mt-1 text-[13px] text-slate">
              {schedule.days} day{schedule.days === 1 ? '' : 's'} · {schedule.workHours}h worked, {schedule.waitHours}h curing
            </div>
            {schedule.waitHours >= 12 && (
              <p className="mt-2 text-[13px] text-warn">
                Long cure closes the unit. Finish lands on a later calendar day.
              </p>
            )}
          </div>
        )}

        {/* Final gap check */}
        {gaps.map((g) => (
          <div key={g.addId} className="rounded-[16px] border border-warn/40 bg-warn/10 p-4">
            <p className="text-[14px] font-semibold">Before you send</p>
            <p className="mt-1 text-[13px] text-slate leading-snug">{g.message}</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => addFamily(g.addId)}
                className="press rounded-full bg-gold text-ink text-[13px] font-bold px-4 py-2"
              >
                {g.addLabel} · {formatMoney(g.priceCents)}
              </button>
              <button
                type="button"
                onClick={() => setSkipGap(true)}
                className="press rounded-full text-[13px] font-medium text-slate border border-ink-line px-3 py-2"
              >
                Send without it
              </button>
            </div>
          </div>
        ))}

        {cart.length > 0 && (
          <div className="flex justify-between items-center pt-2">
            <span className="text-[15px] text-slate">Total</span>
            <span className="mono text-[22px] font-bold">{formatMoney(total)}</span>
          </div>
        )}
        {error && <p className="text-sm text-danger">{error}</p>}
      </main>

      {cart.length > 0 && (
        <div className="fixed bottom-0 inset-x-0 max-w-lg mx-auto p-4 pb-[max(1rem,env(safe-area-inset-bottom))] bg-ink border-t border-ink-line">
          <PrimaryCTA disabled={busy} onClick={send}>
            {busy ? 'Sending…' : 'Send to Thornbury for approval'}
          </PrimaryCTA>
        </div>
      )}
    </div>
  )
}
