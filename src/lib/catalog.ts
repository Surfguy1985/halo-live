export type ServiceCategory =
  | 'Make-ready' | 'Paint' | 'Cleaning' | 'Carpet & Flooring' | 'Resurfacing'
  | 'Repairs' | 'Doors & Trim' | 'Trash Out' | 'Punch' | 'Exterior' | 'Specialty'

export interface ServiceVariant {
  key: string
  priceCents: number
  durationHours: number
  cureHours: number
}

export interface ServiceFamily {
  id: string
  name: string
  category: ServiceCategory
  description: string
  variants: ServiceVariant[]
  follows: string[]
  blocks: string[]
  usual?: boolean
  defaultRooms?: string[]
}

export const CATEGORIES: ServiceCategory[] = [
  'Make-ready', 'Paint', 'Cleaning', 'Carpet & Flooring', 'Resurfacing',
  'Repairs', 'Doors & Trim', 'Trash Out', 'Punch', 'Exterior', 'Specialty',
]

function v(key: string, dollars: number, hours: number, cure = 0): ServiceVariant {
  return { key, priceCents: Math.round(dollars * 100), durationHours: hours, cureHours: cure }
}
function br(d1: number, h1: number, d2: number, h2: number, d3: number, h3: number, cure = 0) {
  return [v('1BR', d1, h1, cure), v('2BR', d2, h2, cure), v('3BR', d3, h3, cure)]
}

export const SERVICE_FAMILIES: ServiceFamily[] = [
  // Make-ready
  { id: 'make_ready', name: 'Make-Ready Package', category: 'Make-ready', description: 'Full turn package for vacant unit', usual: true, variants: br(450, 8, 520, 10, 600, 12), follows: [], blocks: [] },
  { id: 'punch_list', name: 'Punch List Package', category: 'Make-ready', description: 'Walk punch items only', variants: [v('std', 175, 3)], follows: [], blocks: [] },
  // Paint
  { id: 'paint', name: 'Wall Prep & Paint', category: 'Paint', description: 'Prep and topcoat walls', usual: true, variants: br(230, 4, 270, 6, 310, 8, 3), follows: ['kilz'], blocks: ['clean', 'carpet'] },
  { id: 'kilz', name: 'Kilz Primer Seal', category: 'Paint', description: 'Primer before topcoat', usual: true, variants: br(120, 2, 145, 2.5, 170, 3, 3), follows: ['sheetrock'], blocks: ['paint'] },
  { id: 'ceiling_paint', name: 'Ceiling Paint', category: 'Paint', description: 'Flat ceiling coat', variants: br(95, 2, 120, 2.5, 145, 3, 3), follows: [], blocks: [] },
  { id: 'accent_wall', name: 'Accent Wall', category: 'Paint', description: 'Single feature wall', variants: [v('std', 85, 1.5, 3)], follows: [], blocks: [] },
  { id: 'trim_paint', name: 'Trim & Base Paint', category: 'Paint', description: 'Baseboards and casing', variants: br(110, 2, 135, 2.5, 160, 3, 2), follows: [], blocks: [] },
  // Cleaning
  { id: 'clean', name: 'Vacant Unit Clean', category: 'Cleaning', description: 'Full vacant clean', usual: true, variants: br(150, 1.5, 175, 2, 200, 2.5), follows: ['paint', 'resurface', 'carpet'], blocks: [] },
  { id: 'acid_tub', name: 'Acid Wash Bathtub', category: 'Cleaning', description: 'Deep tub clean', usual: true, variants: [v('std', 95, 1)], follows: [], blocks: [] },
  { id: 'oven_clean', name: 'Oven Deep Clean', category: 'Cleaning', description: 'Range and oven', variants: [v('std', 65, 1)], follows: [], blocks: [] },
  { id: 'fridge_clean', name: 'Refrigerator Clean', category: 'Cleaning', description: 'Interior and exterior', variants: [v('std', 45, 0.75)], follows: [], blocks: [] },
  { id: 'window_clean', name: 'Interior Window Clean', category: 'Cleaning', description: 'Glass and tracks', variants: br(55, 1, 75, 1.5, 95, 2), follows: [], blocks: [] },
  { id: 'blinds_clean', name: 'Blind Clean', category: 'Cleaning', description: 'Dust and wipe blinds', variants: br(40, 0.75, 55, 1, 70, 1.25), follows: [], blocks: [] },
  // Carpet & Flooring
  { id: 'carpet', name: 'Carpet Clean', category: 'Carpet & Flooring', description: 'Clean and dry', usual: true, variants: br(95, 1.5, 115, 2, 135, 2.5, 3), follows: ['paint'], blocks: ['clean'] },
  { id: 'carpet_stretch', name: 'Carpet Stretch', category: 'Carpet & Flooring', description: 'Re-stretch and re-tack', variants: [v('room', 125, 2)], follows: [], blocks: [] },
  { id: 'vinyl_plank', name: 'Vinyl Plank Repair', category: 'Carpet & Flooring', description: 'Replace damaged planks', variants: [v('std', 180, 2)], follows: [], blocks: [] },
  { id: 'grout_clean', name: 'Grout Clean & Seal', category: 'Carpet & Flooring', description: 'Bath and kitchen tile', variants: [v('std', 140, 2.5)], follows: [], blocks: [] },
  // Resurfacing
  { id: 'resurface', name: 'Garden Tub Resurface', category: 'Resurfacing', description: 'Spray tub — unit closed 24h', usual: true, variants: [v('std', 375, 2, 24)], follows: [], blocks: ['clean'] },
  { id: 'counter_resurface', name: 'Countertop Resurface', category: 'Resurfacing', description: 'Laminate or cultured marble', variants: [v('std', 425, 3, 12)], follows: [], blocks: [] },
  { id: 'sink_resurface', name: 'Sink Resurface', category: 'Resurfacing', description: 'Bath or kitchen sink', variants: [v('std', 195, 1.5, 12)], follows: [], blocks: [] },
  // Repairs
  { id: 'sheetrock', name: 'Sheetrock Repair', category: 'Repairs', description: 'Patch and mud', usual: true, variants: [v('std', 185, 4, 18)], follows: [], blocks: ['kilz', 'paint'] },
  { id: 'texture_match', name: 'Texture Match', category: 'Repairs', description: 'Match existing wall texture', variants: [v('std', 95, 2, 6)], follows: ['sheetrock'], blocks: ['paint'] },
  { id: 'appliance_repair', name: 'Appliance Repair Call', category: 'Repairs', description: 'Diagnose and minor fix', variants: [v('std', 125, 1.5)], follows: [], blocks: [] },
  { id: 'faucet_replace', name: 'Faucet Replace', category: 'Repairs', description: 'Supply and install faucet', variants: [v('std', 165, 1.5)], follows: [], blocks: [] },
  { id: 'toilet_replace', name: 'Toilet Replace', category: 'Repairs', description: 'Remove and install toilet', variants: [v('std', 220, 2)], follows: [], blocks: [] },
  { id: 'light_fixture', name: 'Light Fixture Replace', category: 'Repairs', description: 'Swap ceiling or vanity light', variants: [v('std', 95, 1)], follows: [], blocks: [] },
  { id: 'outlet_replace', name: 'Outlet / Switch Replace', category: 'Repairs', description: 'Device replace', variants: [v('each', 45, 0.5)], follows: [], blocks: [] },
  // Doors & Trim
  { id: 'doors', name: 'Doors & Trim', category: 'Doors & Trim', description: 'Doors, frames, trim touch-up', usual: true, variants: [v('std', 140, 3)], follows: [], blocks: [] },
  { id: 'door_replace', name: 'Interior Door Replace', category: 'Doors & Trim', description: 'Slab and hardware', variants: [v('std', 275, 2)], follows: [], blocks: [] },
  { id: 'lock_rekey', name: 'Rekey Locks', category: 'Doors & Trim', description: 'Unit rekey set', variants: [v('std', 85, 1)], follows: [], blocks: [] },
  { id: 'closet_door', name: 'Closet Door Adjust', category: 'Doors & Trim', description: 'Bifold or sliding adjust', variants: [v('std', 65, 1)], follows: [], blocks: [] },
  // Trash Out
  { id: 'trash', name: 'Trash Out', category: 'Trash Out', description: 'Clear unit debris', usual: true, variants: [v('std', 85, 2)], follows: [], blocks: [] },
  { id: 'trash_heavy', name: 'Heavy Trash Out', category: 'Trash Out', description: 'Furniture and bulk', variants: [v('std', 175, 3)], follows: [], blocks: [] },
  { id: 'haul_dumpster', name: 'Dumpster Haul', category: 'Trash Out', description: 'Coordinate dumpster load', variants: [v('std', 350, 4)], follows: [], blocks: [] },
  // Punch
  { id: 'punch_paint', name: 'Punch Paint Touch-up', category: 'Punch', description: 'Small paint fixes after walk', variants: [v('std', 75, 1.5, 2)], follows: [], blocks: [] },
  { id: 'punch_clean', name: 'Punch Clean', category: 'Punch', description: 'Spot clean after punch walk', variants: [v('std', 65, 1)], follows: [], blocks: [] },
  { id: 'punch_caulk', name: 'Punch Caulk', category: 'Punch', description: 'Wet area re-caulk', variants: [v('std', 55, 1)], follows: [], blocks: [] },
  // Exterior
  { id: 'patio_clean', name: 'Patio / Balcony Clean', category: 'Exterior', description: 'Sweep and wash patio', variants: [v('std', 55, 1)], follows: [], blocks: [] },
  { id: 'entry_clean', name: 'Entry Door Clean', category: 'Exterior', description: 'Clean and wipe entry', variants: [v('std', 35, 0.5)], follows: [], blocks: [] },
  { id: 'garage_sweep', name: 'Garage Sweep', category: 'Exterior', description: 'Sweep and clear garage', variants: [v('std', 45, 0.75)], follows: [], blocks: [] },
  // Specialty
  { id: 'odor_treat', name: 'Odor Treatment', category: 'Specialty', description: 'Ozone or enzyme treatment', variants: [v('std', 225, 2, 6)], follows: [], blocks: ['clean'] },
  { id: 'pest_spot', name: 'Pest Spot Treatment', category: 'Specialty', description: 'Targeted treatment', variants: [v('std', 95, 1)], follows: [], blocks: [] },
  { id: 'smoke_detector', name: 'Smoke / CO Check', category: 'Specialty', description: 'Test and replace batteries', variants: [v('std', 35, 0.5)], follows: [], blocks: [] },

  { id: 'baseboard', name: 'Baseboard Replace', category: 'Doors & Trim', description: 'Replace damaged baseboard sections', variants: [v('std', 95, 2)], follows: [], blocks: [] },
  { id: 'cabinet_adj', name: 'Cabinet Adjust', category: 'Repairs', description: 'Hinges and alignment', variants: [v('std', 75, 1.5)], follows: [], blocks: [] },
  { id: 'screen_repair', name: 'Window Screen Repair', category: 'Exterior', description: 'Rescreen or replace', variants: [v('each', 55, 0.75)], follows: [], blocks: [] },
  { id: 'mail_key', name: 'Mailbox Key', category: 'Specialty', description: 'Cut and issue mailbox key', variants: [v('std', 25, 0.25)], follows: [], blocks: [] },
  { id: 'dryer_vent', name: 'Dryer Vent Clean', category: 'Cleaning', description: 'Clear dryer vent path', variants: [v('std', 85, 1)], follows: [], blocks: [] },
  { id: 'gutter_clear', name: 'Gutter Clear', category: 'Exterior', description: 'Clear debris from gutters', variants: [v('std', 120, 2)], follows: [], blocks: [] },
  { id: 'pressure_wash', name: 'Entry Pressure Wash', category: 'Exterior', description: 'Wash entry and walk', variants: [v('std', 95, 1.5)], follows: [], blocks: [] },
  { id: 'shower_door', name: 'Shower Door Adjust', category: 'Repairs', description: 'Track and seal', variants: [v('std', 110, 1.5)], follows: [], blocks: [] },
  { id: 'mirror_replace', name: 'Mirror Replace', category: 'Repairs', description: 'Vanity or wall mirror', variants: [v('std', 145, 1)], follows: [], blocks: [] },
  { id: 'threshold', name: 'Door Threshold', category: 'Doors & Trim', description: 'Replace threshold', variants: [v('std', 85, 1)], follows: [], blocks: [] },
]

export type CartLine = {
  familyId: string
  name: string
  variantKey: string
  priceCents: number
  durationHours: number
  cureHours: number
  qty: number
  rooms?: string[]
  note?: string
  outsidePo?: boolean
}

const CART_KEY = 'halo-live-cart-v2'
const UNIT_KEY = 'halo-live-walk-unit'

export function loadCart(): CartLine[] {
  try {
    const raw = localStorage.getItem(CART_KEY)
    return raw ? (JSON.parse(raw) as CartLine[]) : []
  } catch { return [] }
}

export function saveCart(lines: CartLine[]) {
  localStorage.setItem(CART_KEY, JSON.stringify(lines))
}

export function clearCart() {
  localStorage.removeItem(CART_KEY)
}

export function setWalkUnit(u: { unit: string; bedrooms: number; property: string }) {
  localStorage.setItem(UNIT_KEY, JSON.stringify(u))
}

export function getWalkUnit(): { unit: string; bedrooms: number; property: string } | null {
  try {
    const raw = localStorage.getItem(UNIT_KEY)
    return raw ? JSON.parse(raw) : null
  } catch { return null }
}

export function resolveVariant(family: ServiceFamily, bedrooms: number): ServiceVariant {
  const key = bedrooms >= 3 ? '3BR' : bedrooms === 2 ? '2BR' : '1BR'
  return family.variants.find((v) => v.key === key) || family.variants[0]
}

export function cartTotalCents(lines: CartLine[]): number {
  return lines.filter((l) => !l.outsidePo).reduce((s, l) => s + l.priceCents * l.qty, 0)
}

export function formatMoney(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`
}

export function sequenceGaps(lines: CartLine[]): { message: string; addId: string; addLabel: string; priceCents: number }[] {
  const ids = new Set(lines.map((l) => l.familyId))
  const out: { message: string; addId: string; addLabel: string; priceCents: number }[] = []
  if (ids.has('sheetrock') && !ids.has('kilz')) {
    out.push({
      message: 'Sheetrock without primer — mud bleeds through topcoat and the wall gets repainted.',
      addId: 'kilz', addLabel: 'Add Kilz Primer Seal', priceCents: 12000,
    })
  }
  if (ids.has('kilz') && !ids.has('paint')) {
    out.push({
      message: 'Primer is not a finish. Add topcoat paint.',
      addId: 'paint', addLabel: 'Add Wall Prep & Paint', priceCents: 23000,
    })
  }
  if ((ids.has('paint') || ids.has('resurface')) && !ids.has('clean')) {
    out.push({
      message: 'Paint or resurfacing leaves dust and overspray. Units that skip the clean come back on the punch list.',
      addId: 'clean', addLabel: 'Add Vacant Unit Clean', priceCents: 15000,
    })
  }
  return out.slice(0, 1)
}

export function projectSchedule(lines: CartLine[]) {
  let work = 0
  let wait = 0
  for (const l of lines) {
    work += l.durationHours * l.qty
    wait += l.cureHours * l.qty
  }
  const days = Math.max(1, Math.ceil((work + wait) / 10))
  return {
    days,
    workHours: Math.round(work * 10) / 10,
    waitHours: Math.round(wait * 10) / 10,
    finishLabel: days === 1 ? 'Same day if started early' : `${days} calendar days`,
  }
}

export function getFamily(id: string): ServiceFamily | undefined {
  return SERVICE_FAMILIES.find((f) => f.id === id)
}

export const CATALOG_COUNT = SERVICE_FAMILIES.length
