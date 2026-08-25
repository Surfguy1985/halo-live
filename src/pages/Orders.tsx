import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowLeft, Loader2, ShoppingBag } from 'lucide-react'
import { listLiveOrders, type LiveOrder } from '@/lib/api'
import { StatusChip } from '@/components/StatusChip'
import { formatMoney } from '@/lib/catalog'

export default function Orders() {
  const [orders, setOrders] = useState<LiveOrder[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    listLiveOrders().then((r) => {
      setOrders(r.orders)
      setError(r.error || null)
      setLoading(false)
    })
  }, [])

  return (
    <div className="min-h-full theme-light bg-paper text-ink page-enter max-w-lg mx-auto">
      <header className="sticky top-0 z-20 flex h-14 items-center gap-3 border-b border-line px-3 bg-white/95 backdrop-blur">
        <Link to="/live" className="press grid h-10 w-10 place-items-center rounded-full hover:bg-line/50">
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <div className="text-[17px] font-semibold flex-1">Orders</div>
        <Link to="/order" className="text-[14px] font-semibold text-gold-deep px-2">
          New
        </Link>
      </header>

      <main className="px-[22px] py-5 pb-32">
        {loading && (
          <div className="flex justify-center py-16 text-text-muted">
            <Loader2 className="h-6 w-6 animate-spin" />
          </div>
        )}
        {!loading && !orders.length && (
          <div className="text-center py-16">
            <ShoppingBag className="h-10 w-10 mx-auto text-text-muted mb-3" strokeWidth={1.25} />
            <p className="text-[16px] font-semibold text-ink">No orders yet</p>
            <p className="mt-2 text-[14px] text-text-muted">
              Field walks build the first order. It lands here for PO authorize.
            </p>
            <Link
              to="/order"
              className="mt-6 inline-flex rounded-full bg-gold text-ink font-bold text-[14px] px-5 py-2.5"
            >
              Request work
            </Link>
            {error && <p className="mt-3 text-[12px] text-danger">{error}</p>}
          </div>
        )}
        <ul className="space-y-2">
          {orders.map((o) => (
            <li key={o.id}>
              <Link
                to="/approve"
                className="press block rounded-[16px] border border-line bg-white p-4"
              >
                <div className="flex justify-between gap-2 mb-1">
                  <span className="mono text-[15px] font-bold">Unit {o.unit}</span>
                  <StatusChip status={o.status} />
                </div>
                <div className="text-[14px] text-text-muted line-clamp-2">{o.serviceLabel}</div>
                <div className="mt-2 flex justify-between text-[12px] mono text-text-muted">
                  <span>{o.jobNo || o.id.slice(0, 8)}</span>
                  {o.priceCents != null && <span>{formatMoney(o.priceCents)}</span>}
                  {o.poNumber && <span>PO {o.poNumber}</span>}
                </div>
              </Link>
            </li>
          ))}
        </ul>
      </main>
    </div>
  )
}
