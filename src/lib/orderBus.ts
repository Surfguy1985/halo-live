import type { CartLine } from './catalog'
import { cartTotalCents, projectSchedule, getWalkUnit } from './catalog'

export type SharedOrder = {
  unit: string
  property: string
  bedrooms: number
  lines: CartLine[]
  totalCents: number
  schedule: ReturnType<typeof projectSchedule>
  status: 'draft' | 'sent' | 'authorized' | 'dispatched'
  po?: string
  haloJobId?: string
  jobNo?: string
  updatedAt: string
}

const KEY = 'halo-live-shared-order'

export function publishOrderFromCart(
  lines: CartLine[],
  status: SharedOrder['status'] = 'sent',
  extra?: { haloJobId?: string; jobNo?: string },
): SharedOrder {
  const unit = getWalkUnit() || { unit: '1713', bedrooms: 1, property: 'Thornbury at Chase Oaks' }
  const order: SharedOrder = {
    unit: unit.unit,
    property: unit.property,
    bedrooms: unit.bedrooms,
    lines,
    totalCents: cartTotalCents(lines),
    schedule: projectSchedule(lines),
    status,
    haloJobId: extra?.haloJobId,
    jobNo: extra?.jobNo,
    updatedAt: new Date().toISOString(),
  }
  localStorage.setItem(KEY, JSON.stringify(order))
  return order
}

export function loadSharedOrder(): SharedOrder | null {
  try {
    const raw = localStorage.getItem(KEY)
    return raw ? (JSON.parse(raw) as SharedOrder) : null
  } catch {
    return null
  }
}

export function patchSharedOrder(patch: Partial<SharedOrder>) {
  const o = loadSharedOrder()
  if (!o) return null
  const next = { ...o, ...patch, updatedAt: new Date().toISOString() }
  localStorage.setItem(KEY, JSON.stringify(next))
  return next
}

export function authorizeSharedOrder(po: string) {
  return patchSharedOrder({ status: 'authorized', po })
}


export type DispatchPing = {
  serviceName: string
  unit: string
  property: string
  priceCents: number
  crewName: string
  jobId?: string
}

const PING_KEY = 'halo-live-dispatch-ping'

export function queueCrewPing(ping: DispatchPing) {
  localStorage.setItem(PING_KEY, JSON.stringify(ping))
}

export function loadCrewPing(): DispatchPing | null {
  try {
    const raw = localStorage.getItem(PING_KEY)
    return raw ? (JSON.parse(raw) as DispatchPing) : null
  } catch {
    return null
  }
}

export function clearCrewPing() {
  localStorage.removeItem(PING_KEY)
}
