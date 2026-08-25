/**
 * Service menu — HALO_02 style: packages + green checkout bar
 */
import { useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { ArrowLeft, Plus, Search } from 'lucide-react'
import {
  SERVICE_FAMILIES, CATEGORIES, getWalkUnit, loadCart, saveCart,
  resolveVariant, cartTotalCents, formatMoney, sequenceGaps, type CartLine,
} from '@/lib/catalog'
import { loadClientSetup } from '@/lib/onboarding'
import { cn } from '@/lib/cn'
import { ServiceDetail } from '@/components/ServiceDetail'
import type { ServiceFamily } from '@/lib/catalog'

const PACKAGES = [
  {
    id: 'pkg-full',
    name: 'Full Make-Ready',
    detail: 'Paint, carpet, clean, punch · 3-day turn',
    priceCents: 285000,
    serviceIds: ['paint', 'carpet', 'clean', 'punch'] as string[],
  },
  {
    id: 'pkg-punch',
    name: 'Punch + QC Walk',
    detail: 'Photo-documented · Same day',
    priceCents: 48000,
    serviceIds: ['punch'] as string[],
  },
  {
    id: 'pkg-emergency',
    name: 'Emergency Turn',
    detail: 'Crew dispatched within 2 hours',
    priceCents: 85000,
    serviceIds: ['clean', 'punch'] as string[],
  },
]

export default function OrderMenu() {
  const nav = useNavigate()
  const unit = getWalkUnit() || { unit: '1713', bedrooms: 1, property: 'Thornbury at Chase Oaks' }
  const setup = loadClientSetup()
  const propertyName = setup?.propertyName || unit.property
  const [cart, setCart] = useState<CartLine[]>(() => loadCart())
  const [q, setQ] = useState('')
  const [detail, setDetail] = useState<ServiceFamily | null>(null)
  const [cat, setCat] = useState<string | null>(null)

  const total = cartTotalCents(cart)
  const gaps = sequenceGaps(cart)

  const filtered = useMemo(() => {
    let list = SERVICE_FAMILIES
    if (cat) list = list.filter((f) => f.category === cat)
    if (q.trim()) {
      const s = q.toLowerCase()
      list = list.filter(
        (f) => f.name.toLowerCase().includes(s) || f.category.toLowerCase().includes(s),
      )
    }
    return list
  }, [q, cat])

  function persist(next: CartLine[]) {
    setCart(next)
    saveCart(next)
  }

  function addFamily(f: ServiceFamily) {
    const v = resolveVariant(f, unit.bedrooms)
    const existing = cart.find((c) => c.familyId === f.id && c.variantId === v.id)
    if (existing) {
      persist(cart.map((c) => (c === existing ? { ...c, qty: c.qty + 1 } : c)))
    } else {
      persist([
        ...cart,
        {
          familyId: f.id,
          name: f.name,
          variantId: v.id,
          variantLabel: v.label,
          priceCents: v.priceCents,
          durationHours: v.durationHours,
          cureHours: v.cureHours || 0,
          qty: 1,
        },
      ])
    }
  }

  function addPackage(pkg: (typeof PACKAGES)[0]) {
    let next = [...cart]
    for (const sid of pkg.serviceIds) {
      const f = SERVICE_FAMILIES.find((x) => x.id === sid)
      if (!f) continue
      const v = resolveVariant(f, unit.bedrooms)
      if (!next.some((c) => c.familyId === f.id)) {
        next.push({
          familyId: f.id,
          name: f.name,
          variantId: v.id,
          variantLabel: v.label,
          priceCents: v.priceCents,
          durationHours: v.durationHours,
          cureHours: v.cureHours || 0,
          qty: 1,
        })
      }
    }
    // If package price is package-level, user still sees line items; total from lines
    persist(next)
  }

  return (
    <div className="min-h-full theme-light bg-white text-ink page-enter max-w-lg mx-auto pb-36">
      <header className="sticky top-0 z-20 bg-white/95 backdrop-blur border-b border-black/[0.04] px-[22px] pt-[max(0.75rem,env(safe-area-inset-top))] pb-3">
        <div className="flex items-center gap-2 text-[11px] font-semibold tracking-[0.14em] uppercase">
          <Link to="/units" className="text-text-muted">
            <ArrowLeft className="h-5 w-5" />
          </Link>
          <span className="text-[#00C853]">HALO</span>
          <span className="text-text-muted">·</span>
          <span className="text-[#00C853]">Order services</span>
        </div>
        <h1 className="mt-2 text-[26px] font-bold tracking-[-0.03em]">{propertyName}</h1>
        <p className="text-[13px] text-text-muted mt-0.5">
          Unit {setup?.unitDemo || unit.unit} · Add packages or individual services
        </p>
        <div className="mt-3 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-text-muted" />
          <input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="Search services"
            className="w-full rounded-full bg-[#F4F4F0] border-0 pl-10 pr-4 py-2.5 text-[14px] outline-none focus:ring-2 focus:ring-[#00C853]/30"
          />
        </div>
      </header>

      <main className="px-[22px] py-4 space-y-6">
        {/* Packages — ServiceMenu video */}
        <section>
          <div className="text-[11px] font-semibold tracking-[0.14em] uppercase text-text-muted mb-3">
            Packages
          </div>
          <div className="space-y-2">
            {PACKAGES.map((pkg) => (
              <div
                key={pkg.id}
                className="rounded-[14px] bg-[#F7F7F5] px-4 py-4 flex items-center gap-3"
              >
                <div className="flex-1 min-w-0">
                  <div className="text-[16px] font-semibold">{pkg.name}</div>
                  <div className="text-[13px] text-text-muted mt-0.5">{pkg.detail}</div>
                  <div className="mono text-[15px] font-bold mt-1.5">{formatMoney(pkg.priceCents)}</div>
                </div>
                <button
                  type="button"
                  onClick={() => addPackage(pkg)}
                  className="press shrink-0 text-[#00C853] font-bold text-[13px] tracking-wide"
                >
                  + ADD
                </button>
              </div>
            ))}
          </div>
        </section>

        {/* Category chips */}
        <div className="flex gap-2 overflow-x-auto no-scrollbar -mx-[22px] px-[22px]">
          <button
            type="button"
            onClick={() => setCat(null)}
            className={cn(
              'shrink-0 rounded-full px-3.5 py-1.5 text-[13px] font-medium border',
              !cat ? 'bg-ink text-white border-ink' : 'bg-white border-line text-text-muted',
            )}
          >
            All
          </button>
          {CATEGORIES.map((c) => (
            <button
              key={c}
              type="button"
              onClick={() => setCat(c === cat ? null : c)}
              className={cn(
                'shrink-0 rounded-full px-3.5 py-1.5 text-[13px] font-medium border',
                cat === c ? 'bg-ink text-white border-ink' : 'bg-white border-line text-text-muted',
              )}
            >
              {c}
            </button>
          ))}
        </div>

        {gaps.length > 0 && (
          <div className="rounded-[12px] border border-warn/40 bg-warn/10 px-3 py-2 text-[13px] text-ink">
            Suggested next: {gaps[0]}
          </div>
        )}

        <section className="space-y-2">
          {filtered.map((f) => {
            const v = resolveVariant(f, unit.bedrooms)
            const inCart = cart.some((c) => c.familyId === f.id)
            return (
              <div
                key={f.id}
                className="rounded-[14px] border border-line px-4 py-3.5 flex items-center gap-3"
              >
                <button type="button" className="flex-1 text-left min-w-0" onClick={() => setDetail(f)}>
                  <div className="text-[15px] font-semibold">{f.name}</div>
                  <div className="text-[12px] text-text-muted mt-0.5 line-clamp-1">{f.description}</div>
                  <div className="mono text-[14px] font-bold mt-1">{formatMoney(v.priceCents)}</div>
                </button>
                <button
                  type="button"
                  onClick={() => addFamily(f)}
                  className={cn(
                    'press shrink-0 h-9 w-9 rounded-full grid place-items-center',
                    inCart ? 'bg-[#00C853] text-white' : 'bg-[#F4F4F0] text-ink',
                  )}
                >
                  <Plus className="h-4 w-4" strokeWidth={2.5} />
                </button>
              </div>
            )
          })}
        </section>
      </main>

      {/* Green sticky checkout — matches ServiceMenu video */}
      {cart.length > 0 && (
        <div className="fixed bottom-[calc(3.5rem+env(safe-area-inset-bottom))] inset-x-0 z-30 px-3 max-w-lg mx-auto">
          <button
            type="button"
            onClick={() => nav('/order/checkout')}
            className="press w-full rounded-[14px] bg-[#00C853] text-white px-5 py-3.5 flex items-center justify-between shadow-lg"
          >
            <div className="text-left">
              <div className="text-[15px] font-bold">
                Checkout · {cart.reduce((n, c) => n + c.qty, 0)} services
              </div>
              <div className="text-[12px] opacity-90">Review before sending to property</div>
            </div>
            <div className="mono text-[18px] font-bold">{formatMoney(total)}</div>
          </button>
        </div>
      )}

      {detail && (
        <ServiceDetail
          family={detail}
          bedrooms={unit.bedrooms}
          onClose={() => setDetail(null)}
          onAdd={(line) => {
            persist([...cart.filter((c) => c.familyId !== line.familyId), line])
            setDetail(null)
          }}
        />
      )}
    </div>
  )
}
