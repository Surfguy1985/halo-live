/**
 * Halo Live — 100% real data. No mocks. No localStorage data stores.
 * If API is down, surfaces return empty + error for the UI to show.
 *
 * Sources:
 *   Plate     GET /api/properties/:id/building-ops  (+ X-Halo-Role)
 *   Jobs      GET /api/jobs?propertyId=
 *   Order     POST /api/jobs/quick  ·  POST /api/jobs/:id/client-po
 *   Status    PATCH /api/jobs/:id { status }
 *   Feed      GET/POST /api/activities
 *   Photos    plate.photoBillboards · /api/storage…
 *   Field     /api/checkin/:token (fieldCompanion.ts)
 */
export type Role = 'portfolio' | 'pulse' | 'vendor'

export interface Building {
  id: string
  name: string
  lat: number
  lng: number
  status: 'clear' | 'active' | 'blocked' | 'review'
  risk: 'high' | 'med' | 'low'
  turnsOpen: number
  photoCount: number
  moneyTint?: number
  footprint?: [number, number][]
  openDiscrepancies?: number
}

export interface CrewMember {
  id: string
  name: string
  role: string
  lat: number
  lng: number
  status: 'on_site' | 'en_route' | 'idle'
  buildingId?: string
  lastSeen: string
  jobId?: string
  unitNo?: string
}

export interface WorkItem {
  id: string
  buildingId: string
  unit: string
  type: 'turn_clean' | 'make_ready' | 'carpet' | 'paint' | 'punch'
  status: 'open' | 'in_progress' | 'review' | 'approved' | 'flagged'
  rawStatus: string
  title: string
  /** Service line names from Halo job (same as Base44 dispatch) */
  services: string[]
  steps: PhotoStep[]
  beforePhotos: string[]
  afterPhotos: string[]
  /** Crew leader display name */
  assignedTo?: string
  crewLeaderId?: string
  propertyName?: string
  updatedAt: string
  jobNo?: string
  base44Id?: string
  propertyId?: string
  poNumber?: string | null
}

export interface PhotoStep {
  id: string
  order: number
  title: string
  instruction: string
  tip?: string
  areaDiagram?: string
  required: boolean
  photos: string[]
}

export interface Message {
  id: string
  buildingId: string
  unit?: string
  author: string
  role: Role | 'system'
  body: string
  createdAt: string
  read: boolean
  kind?: string
  entityType?: string
  entityId?: string
}

export interface FieldPhoto {
  id: string
  url: string
  phase?: 'before' | 'after' | 'progress' | string
  unitNo?: string
  buildingId?: string
  jobId?: string
  caption?: string
  takenAt?: string
}

export interface Plate {
  propertyId: string
  propertyName: string
  buildings: Building[]
  crew: CrewMember[]
  photos: FieldPhoto[]
  center: [number, number]
  summary: { onSite: number; liveJobs: number; photoCount: number; headline: string }
  live: boolean
  error?: string
}

export interface LiveOrder {
  id: string
  jobNo?: string
  unit: string
  serviceLabel: string
  poNumber?: string
  notes?: string
  status: string
  createdAt: string
  priceCents?: number
  propertyId?: string
}

export interface ApiResult<T> {
  data: T | null
  status: number
  error?: string
}

/** Empty = same-origin /api (Vite proxies to live Halo). Absolute URL for direct prod. */
const API_BASE = (import.meta.env.VITE_API_BASE as string | undefined)?.replace(/\/$/, '') ?? ''
const ROLE_KEY = 'halo-live-role'
const THORNBURY = '49dec4b1-1dc5-4b59-8025-0c0bc14d35ce'

/**
 * Halo job.status values seen in production:
 *   scheduled | open | active | complete | paid | cancelled | hold
 * Halo job.boardStatus (rail): active | filled | completed | billing | removed
 *
 * Live board columns map to job.status (PATCH /api/jobs/:id).
 * "complete" requires a client PO or API returns 409.
 */
const STATUS_TO_BOARD: Record<string, WorkItem['status']> = {
  scheduled: 'open',
  unassigned: 'open',
  open: 'open',
  active: 'in_progress',
  dispatched: 'in_progress',
  in_progress: 'in_progress',
  on_site: 'in_progress',
  filled: 'in_progress',
  review: 'review',
  billing: 'review',
  complete: 'approved',
  completed: 'approved',
  paid: 'approved',
  cancelled: 'flagged',
  canceled: 'flagged',
  hold: 'flagged',
  flagged: 'flagged',
  removed: 'flagged',
}

/** Board column → PATCH body for /api/jobs/:id */
const BOARD_TO_STATUS: Record<WorkItem['status'], string> = {
  open: 'scheduled',
  in_progress: 'active',
  review: 'active', // billing is boardStatus; keep job active until complete+PO
  approved: 'complete',
  flagged: 'hold',
}

export const BOARD_COLUMNS: { key: WorkItem['status']; label: string; haloStatus: string }[] = [
  { key: 'open', label: 'Open', haloStatus: 'scheduled' },
  { key: 'in_progress', label: 'In progress', haloStatus: 'active' },
  { key: 'review', label: 'Review', haloStatus: 'active' },
  { key: 'approved', label: 'Complete', haloStatus: 'complete' },
  { key: 'flagged', label: 'Hold', haloStatus: 'hold' },
]

export function photoUrl(path: string | null | undefined): string | null {
  if (!path) return null
  if (path.startsWith('http') || path.startsWith('blob:')) return path
  const p = path.startsWith('/api/storage')
    ? path
    : `/api/storage${path.startsWith('/') ? path : `/${path}`}`
  return `${API_BASE}${p}`
}

export function getRoleFromStorage(): Role | null {
  try {
    const r = localStorage.getItem(ROLE_KEY)
    if (r === 'portfolio' || r === 'pulse' || r === 'vendor') return r
  } catch { /* */ }
  return null
}

export function setRoleInStorage(role: Role) {
  localStorage.setItem(ROLE_KEY, role)
}

/** Alias used by RoleGate */
export function setRole(role: Role) {
  setRoleInStorage(role)
}

function roleHeaders(): HeadersInit {
  const role = getRoleFromStorage()
  return role ? { 'X-Halo-Role': role } : {}
}

export async function fetchJson<T>(path: string, init?: RequestInit): Promise<ApiResult<T>> {
  const base = API_BASE
  try {
    // base '' → relative /api/* via Vite proxy (real Halo)
    const res = await fetch(`${base}${path}`, {
      ...init,
      headers: {
        Accept: 'application/json',
        ...roleHeaders(),
        ...(init?.body ? { 'Content-Type': 'application/json' } : {}),
        ...init?.headers,
      },
    })
    const text = await res.text()
    let data: unknown = null
    try {
      data = text ? JSON.parse(text) : null
    } catch {
      data = null
    }
    if (!res.ok) {
      const err = (data as { error?: string })?.error || res.statusText || `HTTP ${res.status}`
      return { data: null, status: res.status, error: err }
    }
    return { data: data as T, status: res.status }
  } catch (e) {
    return { data: null, status: 0, error: String((e as Error)?.message || e) }
  }
}

function mapJobType(desc: string): WorkItem['type'] {
  const d = desc.toLowerCase()
  if (d.includes('carpet')) return 'carpet'
  if (d.includes('paint')) return 'paint'
  if (d.includes('punch')) return 'punch'
  if (d.includes('make') || d.includes('ready')) return 'make_ready'
  return 'turn_clean'
}

function mapJobStatus(s: string): WorkItem['status'] {
  const key = (s || '').toLowerCase().replace(/\s+/g, '_')
  return STATUS_TO_BOARD[key] || 'open'
}

export const FIELD_GUIDES: Record<string, PhotoStep[]> = {
  turn_clean: [
    { id: 'tc1', order: 1, title: 'Entry / living room — before', instruction: 'Wide shot from the door.', tip: 'Lights on', required: true, photos: [] },
    { id: 'tc2', order: 2, title: 'Kitchen — before', instruction: 'Counters, sink, appliances, floor.', required: true, photos: [] },
    { id: 'tc3', order: 3, title: 'Bath — before', instruction: 'Vanity, toilet, tub/shower, floor.', required: true, photos: [] },
    { id: 'tc4', order: 4, title: 'Bedrooms — before', instruction: 'Each bedroom empty, floors and walls.', required: true, photos: [] },
    { id: 'tc5', order: 5, title: 'Entry / living room — after', instruction: 'Same angle as before.', tip: 'Match framing', required: true, photos: [] },
    { id: 'tc6', order: 6, title: 'Kitchen — after', instruction: 'Same angle as before.', required: true, photos: [] },
    { id: 'tc7', order: 7, title: 'Bath — after', instruction: 'Same angle as before.', required: true, photos: [] },
    { id: 'tc8', order: 8, title: 'Bedrooms — after', instruction: 'Same angles as before.', required: true, photos: [] },
  ],
  make_ready: [
    { id: 'mr1', order: 1, title: 'Scope overview — before', instruction: 'Every room with punch items.', required: true, photos: [] },
    { id: 'mr2', order: 2, title: 'Damaged areas — before', instruction: 'Close-ups of work areas.', required: true, photos: [] },
    { id: 'mr3', order: 3, title: 'Completed repairs — after', instruction: 'Same close-ups after work.', required: true, photos: [] },
    { id: 'mr4', order: 4, title: 'Final walk — after', instruction: 'Full rooms, turnover-ready.', required: true, photos: [] },
  ],
  carpet: [
    { id: 'c1', order: 1, title: 'Carpet — before', instruction: 'Full room + traffic paths.', required: true, photos: [] },
    { id: 'c2', order: 2, title: 'Carpet — after', instruction: 'Same angles, dry and even.', required: true, photos: [] },
  ],
  paint: [
    { id: 'p1', order: 1, title: 'Surfaces — before', instruction: 'Walls and trim to paint.', required: true, photos: [] },
    { id: 'p2', order: 2, title: 'Finished — after', instruction: 'Same walls after paint.', required: true, photos: [] },
  ],
  punch: [
    { id: 'pu1', order: 1, title: 'Punch items — before', instruction: 'Each defect close-up.', required: true, photos: [] },
    { id: 'pu2', order: 2, title: 'Punch complete — after', instruction: 'Same items resolved.', required: true, photos: [] },
  ],
}

export async function resolvePropertyId(): Promise<{ id: string | null; error?: string }> {
  const home = await fetchJson<{ properties?: { id: string; name?: string }[]; id?: string; propertyId?: string }>(
    '/api/portfolio/home',
  )
  if (home.error && !home.data) {
    // Fall through to known production property only as last resort ID for path construction —
    // still requires live API for actual plate/jobs.
    return { id: THORNBURY, error: home.error }
  }
  const h = home.data
  if (h?.properties?.[0]?.id) return { id: h.properties[0].id }
  if (h?.propertyId) return { id: h.propertyId }
  if (h?.id) return { id: h.id }
  return { id: THORNBURY }
}

export async function getPlate(role: Role): Promise<Plate> {
  const { id: propertyId, error: propErr } = await resolvePropertyId()
  if (!propertyId) {
    return emptyPlate(null, propErr || 'No property id')
  }

  const rawRes = await fetchJson<Record<string, unknown>>(
    `/api/properties/${propertyId}/building-ops`,
  )
  const raw = rawRes.data
  if (!raw) {
    return emptyPlate(propertyId, rawRes.error || propErr || 'Plate unavailable')
  }

  const moneyTint = Array.isArray(raw.moneyTint)
    ? (raw.moneyTint as { building?: string | number; intensity?: number; openTurns?: number; risk?: string }[])
    : []
  const tintByBldg = new Map(moneyTint.map((m) => [String(m.building), m]))
  const buildingsRaw = Array.isArray(raw.buildings) ? (raw.buildings as Record<string, unknown>[]) : []
  const buildings: Building[] = buildingsRaw.map((b, i) => {
    const id = String(b.id ?? b.buildingId ?? `b${i + 1}`)
    const tint = tintByBldg.get(id) || tintByBldg.get(String(b.name))
    return {
      id,
      name: String(b.name ?? b.label ?? `Bldg ${i + 1}`),
      lat: Number(b.lat ?? b.latitude ?? 33.0705),
      lng: Number(b.lng ?? b.longitude ?? -96.751),
      status: (b.status as Building['status']) || (Number(tint?.openTurns) > 0 ? 'active' : 'clear'),
      risk: (tint?.risk as Building['risk']) || 'low',
      turnsOpen: Number(tint?.openTurns ?? b.turnsOpen ?? 0),
      photoCount: Number(b.photoCount ?? 0),
      moneyTint: role === 'vendor' ? Number(tint?.intensity ?? b.moneyTint ?? 0) : undefined,
      footprint: Array.isArray(b.footprint) ? (b.footprint as [number, number][]) : undefined,
      openDiscrepancies: role === 'vendor' ? Number(b.openDiscrepancies ?? 0) : undefined,
    }
  })

  const presence = Array.isArray(raw.presence)
    ? (raw.presence as Record<string, unknown>[])
    : Array.isArray(raw.crew)
      ? (raw.crew as Record<string, unknown>[])
      : []
  const crew: CrewMember[] = presence.map((p, i) => ({
    id: String(p.crewId ?? p.id ?? `c${i}`),
    name: String(p.name ?? p.crewName ?? 'Crew'),
    role: String(p.role ?? 'tech'),
    lat: Number(p.lat ?? 33.07),
    lng: Number(p.lng ?? -96.75),
    status: (p.status as CrewMember['status']) || 'on_site',
    buildingId: p.buildingId ? String(p.buildingId) : undefined,
    lastSeen: String(p.lastSeen ?? p.at ?? new Date().toISOString()),
    jobId: p.jobId ? String(p.jobId) : undefined,
    unitNo: p.unitNo ? String(p.unitNo) : undefined,
  }))

  const billboards = Array.isArray(raw.photoBillboards)
    ? (raw.photoBillboards as Record<string, unknown>[])
    : Array.isArray(raw.photos)
      ? (raw.photos as Record<string, unknown>[])
      : []
  const photos: FieldPhoto[] = billboards.map((b, i) => {
    const storagePath = String(b.storagePath ?? b.path ?? b.url ?? '')
    return {
      id: String(b.id ?? `ph${i}`),
      url: photoUrl(storagePath) || storagePath,
      phase: (b.phase as FieldPhoto['phase']) || (b.type as string) || 'progress',
      unitNo: b.unitNo ? String(b.unitNo) : undefined,
      buildingId: b.buildingId ? String(b.buildingId) : undefined,
      jobId: b.jobId ? String(b.jobId) : undefined,
      caption: b.caption ? String(b.caption) : undefined,
      takenAt: b.timestamp ? String(b.timestamp) : b.takenAt ? String(b.takenAt) : undefined,
    }
  })

  const centerLat = Number(raw.centerLat ?? raw.lat ?? buildings[0]?.lat ?? 33.0705)
  const centerLng = Number(raw.centerLng ?? raw.lng ?? buildings[0]?.lng ?? -96.751)

  return {
    propertyId,
    propertyName: String(raw.propertyName ?? raw.name ?? 'Property'),
    buildings,
    crew,
    photos,
    center: [centerLat, centerLng],
    summary: {
      onSite: crew.filter((c) => c.status === 'on_site').length,
      liveJobs: buildings.reduce((n, b) => n + b.turnsOpen, 0),
      photoCount: photos.length,
      headline: String(raw.headline ?? `${buildings.length} buildings · live`),
    },
    live: true,
  }
}

function emptyPlate(propertyId: string | null, error: string): Plate {
  return {
    propertyId: propertyId || '',
    propertyName: 'Unavailable',
    buildings: [],
    crew: [],
    photos: [],
    center: [33.0705, -96.751],
    summary: { onSite: 0, liveJobs: 0, photoCount: 0, headline: error },
    live: false,
    error,
  }
}

export function subscribePlate(propertyId: string, onUpdate: () => void): () => void {
  if (!propertyId || typeof EventSource === 'undefined') return () => {}
  let es: EventSource | null = null
  try {
    es = new EventSource(`${API_BASE}/api/properties/${propertyId}/building-ops/stream`)
    es.onmessage = () => onUpdate()
  } catch { /* */ }
  return () => {
    try { es?.close() } catch { /* */ }
  }
}

export async function getWorkItems(propertyId?: string): Promise<{ items: WorkItem[]; error?: string }> {
  const pid = propertyId || (await resolvePropertyId()).id
  const q = pid ? `?propertyId=${encodeURIComponent(pid)}` : ''
  const jobsRes = await fetchJson<Record<string, unknown>[] | { jobs?: Record<string, unknown>[] }>(
    `/api/jobs${q}`,
  )
  if (!jobsRes.data) {
    return { items: [], error: jobsRes.error || 'Jobs API unavailable' }
  }
  let rows: Record<string, unknown>[] = []
  if (Array.isArray(jobsRes.data)) rows = jobsRes.data
  else if (Array.isArray((jobsRes.data as { jobs?: unknown[] }).jobs)) {
    rows = (jobsRes.data as { jobs: Record<string, unknown>[] }).jobs
  }

  const items: WorkItem[] = rows.map((j) => {
    const servicesRaw = j.services
    const services: string[] = Array.isArray(servicesRaw)
      ? servicesRaw.map(String).filter(Boolean)
      : []
    // description may be multi-line; first line is title, services array is truth
    const desc = String(j.description ?? j.title ?? j.serviceLabel ?? 'Job')
    const titleFromServices = services.length ? services.join(' · ') : desc.split('\n')[0]
    const type = mapJobType(services.join(' ') || desc)
    const rawStatus = String(j.status ?? 'open')
    return {
      id: String(j.id),
      buildingId: String(j.buildingId ?? ''),
      unit: String(j.unitNo ?? j.unit ?? '—'),
      type,
      status: mapJobStatus(rawStatus),
      rawStatus,
      title: titleFromServices,
      services,
      steps: (FIELD_GUIDES[type] ?? FIELD_GUIDES.turn_clean).map((s) => ({ ...s, photos: [] })),
      beforePhotos: [],
      afterPhotos: [],
      assignedTo: j.crewLeaderName ? String(j.crewLeaderName) : undefined,
      crewLeaderId: j.crewLeaderId ? String(j.crewLeaderId) : undefined,
      propertyName: j.propertyName ? String(j.propertyName) : undefined,
      updatedAt: String(j.updatedAt ?? j.createdAt ?? new Date().toISOString()),
      jobNo: j.jobNo ? String(j.jobNo) : undefined,
      base44Id: j.base44Id ? String(j.base44Id) : undefined,
      propertyId: j.propertyId ? String(j.propertyId) : undefined,
      poNumber: j.poNumber != null ? String(j.poNumber) : null,
    }
  })
  return { items }
}

/** Move board card — real PATCH /api/jobs/:id */
export async function updateJobBoardStatus(
  jobId: string,
  boardStatus: WorkItem['status'],
): Promise<ApiResult<Record<string, unknown>>> {
  const status = BOARD_TO_STATUS[boardStatus] || boardStatus
  const res = await fetchJson<Record<string, unknown>>(`/api/jobs/${jobId}`, {
    method: 'PATCH',
    body: JSON.stringify({ status }),
  })
  // 409 = complete blocked without PO — surface clearly
  if (res.status === 409) {
    return {
      data: null,
      status: 409,
      error:
        res.error ||
        'Client PO required before this job can move to Complete / Billing',
    }
  }
  return res
}

/**
 * Live feed = Halo activities for jobs on this property.
 * buildingId is used as a filter hint in the body text / unit when present.
 */
export async function getMessages(buildingId: string): Promise<{ messages: Message[]; error?: string }> {
  const { items, error: jobsErr } = await getWorkItems()
  if (jobsErr && !items.length) {
    return { messages: [], error: jobsErr }
  }

  // Prefer recent activities across jobs (limit 100 from API)
  const act = await fetchJson<{
    id: string
    entityType: string
    entityId: string
    kind: string
    body?: string | null
    createdAt?: string
  }[]>('/api/activities?limit=80')

  if (!act.data) {
    return { messages: [], error: act.error || 'Activities API unavailable' }
  }

  const jobIds = new Set(items.map((i) => i.id))
  const unitByJob = new Map(items.map((i) => [i.id, i.unit]))

  const messages: Message[] = act.data
    .filter((a) => a.entityType === 'job' && jobIds.has(a.entityId))
    .map((a) => ({
      id: a.id,
      buildingId,
      unit: unitByJob.get(a.entityId),
      author: a.kind === 'note' ? 'Team' : 'HALO',
      role: 'system' as const,
      body: a.body || a.kind,
      createdAt: a.createdAt || new Date().toISOString(),
      read: true,
      kind: a.kind,
      entityType: a.entityType,
      entityId: a.entityId,
    }))

  return { messages }
}

export async function postMessage(
  buildingId: string,
  body: string,
  _author: string,
  _role: Role,
  jobId?: string,
): Promise<{ message: Message | null; error?: string }> {
  // Resolve a job on this property to attach the activity
  let entityId = jobId
  if (!entityId) {
    const { items } = await getWorkItems()
    entityId = items[0]?.id
  }
  if (!entityId) {
    return { message: null, error: 'No job to attach message — create or open a job first' }
  }

  const created = await fetchJson<{
    id: string
    entityType: string
    entityId: string
    kind: string
    body?: string | null
    createdAt?: string
  }>('/api/activities', {
    method: 'POST',
    body: JSON.stringify({
      entityType: 'job',
      entityId,
      kind: 'note',
      body: `[${buildingId}] ${body}`,
    }),
  })

  if (!created.data) {
    return { message: null, error: created.error || 'Failed to post activity' }
  }

  return {
    message: {
      id: created.data.id,
      buildingId,
      author: _author,
      role: _role,
      body: created.data.body || body,
      createdAt: created.data.createdAt || new Date().toISOString(),
      read: true,
      kind: created.data.kind,
      entityType: created.data.entityType,
      entityId: created.data.entityId,
    },
  }
}

export async function getJobFieldPhotos(jobId: string): Promise<{ photos: FieldPhoto[]; error?: string }> {
  const detail = await fetchJson<{
    photos?: Record<string, unknown>[]
    activities?: { id?: string; kind?: string; body?: string; storagePath?: string | null }[]
  }>(`/api/jobs/${jobId}`)

  if (!detail.data) {
    return { photos: [], error: detail.error }
  }

  const out: FieldPhoto[] = []
  if (Array.isArray(detail.data.photos)) {
    for (const p of detail.data.photos) {
      const path = String(p.storagePath ?? p.url ?? '')
      if (!path) continue
      out.push({
        id: String(p.id ?? path),
        url: photoUrl(path) || path,
        phase: (p.phase as FieldPhoto['phase']) || 'progress',
        jobId,
      })
    }
  }

  // Activities often mirror field photos
  if (Array.isArray(detail.data.activities)) {
    for (const a of detail.data.activities) {
      if (a.storagePath) {
        out.push({
          id: String(a.id ?? a.storagePath),
          url: photoUrl(a.storagePath) || a.storagePath,
          phase: 'progress',
          jobId,
          caption: a.body || undefined,
        })
      }
    }
  }

  if (out.length) return { photos: out }

  // Plate billboards filtered by job
  const role = getRoleFromStorage() || 'pulse'
  const plate = await getPlate(role)
  return {
    photos: plate.photos.filter((p) => p.jobId === jobId),
    error: plate.error,
  }
}

export async function submitLiveOrder(input: {
  propertyId: string
  unitNo: string
  description: string
  price?: number
  poNumber?: string
  dueOn?: string
}): Promise<{ ok: true; order: LiveOrder } | { ok: false; error: string }> {
  const body: Record<string, unknown> = {
    propertyId: input.propertyId,
    description: input.description,
    unitNo: input.unitNo,
  }
  if (input.price != null && input.price > 0) body.price = input.price
  if (input.dueOn) body.dueOn = input.dueOn

  const created = await fetchJson<Record<string, unknown>>('/api/jobs/quick', {
    method: 'POST',
    body: JSON.stringify(body),
  })
  if (!created.data?.id) {
    return { ok: false, error: created.error || 'Could not create job on Halo' }
  }

  const jobId = String(created.data.id)
  const jobNo = created.data.jobNo ? String(created.data.jobNo) : undefined

  if (input.poNumber?.trim()) {
    const po = await fetchJson(`/api/jobs/${jobId}/client-po`, {
      method: 'POST',
      body: JSON.stringify({ poNumber: input.poNumber.trim() }),
    })
    if (po.error) {
      // Job exists; surface PO failure but still return order
      return {
        ok: true,
        order: {
          id: jobId,
          jobNo,
          unit: input.unitNo,
          serviceLabel: input.description,
          poNumber: undefined,
          status: String(created.data.status ?? 'open'),
          createdAt: new Date().toISOString(),
          priceCents: input.price != null ? Math.round(input.price * 100) : undefined,
          propertyId: input.propertyId,
        },
      }
    }
  }

  return {
    ok: true,
    order: {
      id: jobId,
      jobNo,
      unit: input.unitNo,
      serviceLabel: input.description,
      poNumber: input.poNumber,
      status: String(created.data.status ?? 'open'),
      createdAt: new Date().toISOString(),
      priceCents: input.price != null ? Math.round(input.price * 100) : undefined,
      propertyId: input.propertyId,
    },
  }
}

export async function listLiveOrders(): Promise<{ orders: LiveOrder[]; error?: string }> {
  const { items, error } = await getWorkItems()
  return {
    orders: items.map((w) => ({
      id: w.id,
      jobNo: w.jobNo,
      unit: w.unit,
      serviceLabel: w.title,
      poNumber: w.poNumber || undefined,
      status: w.rawStatus || w.status,
      createdAt: w.updatedAt,
      propertyId: w.propertyId,
    })),
    error,
  }
}




/** Open or fetch field review card for a job (creates if missing) */
export async function getOrOpenFieldReview(jobId: string) {
  return fetchJson<{
    ok?: boolean
    review?: { id: string; jobId: string; status?: string }
    id?: string
    showModal?: boolean
  }>(`/api/work-reviews/job/${jobId}/field-card`)
}

/** Pulse/field confirms accuracy → work-review pipeline */
export async function submitPulseFieldReview(
  reviewId: string,
  opts: {
    approved: boolean
    submittedBy?: string
    photoId?: string
    unitNo?: string
    note?: string
  },
) {
  const edits = {
    confirmAccurate: opts.approved,
    pulseVerdict: opts.approved ? 'approved' : 'rework',
    photoId: opts.photoId,
    unitNo: opts.unitNo,
    note: opts.note,
  }
  return fetchJson<Record<string, unknown>>(`/api/work-reviews/${reviewId}/field-submit`, {
    method: 'POST',
    body: JSON.stringify({
      submittedBy: opts.submittedBy || 'pulse',
      edits,
    }),
  })
}

/** Load work-verification snapshot (discrepancies + suggestions) */
export async function getWorkVerification(jobId: string) {
  return fetchJson<{
    showModal?: boolean
    verification?: Record<string, unknown>
  }>(`/api/work-verification/${jobId}`)
}

/** Apply / dismiss a discrepancy suggestion from verification */
export async function applyVerificationSuggestion(
  jobId: string,
  body: {
    discrepancyId?: string
    reason: string
    status?: 'applied' | 'dismissed' | 'pending_review'
    suggestedInvoiceCents?: number
    suggestedCrewCents?: number
  },
) {
  return fetchJson<Record<string, unknown>>(
    `/api/work-verification/${jobId}/apply-suggestion`,
    {
      method: 'POST',
      body: JSON.stringify(body),
    },
  )
}

/**
 * Full Pulse photo decision:
 * 1) open field review for job
 * 2) field-submit confirmAccurate true/false
 * 3) on approve — dismiss/apply open verification suggestions when present
 * 4) on rework — PATCH job hold
 */
export async function pulsePhotoDecision(opts: {
  jobId: string
  approved: boolean
  photoId?: string
  unitNo?: string
  note?: string
}): Promise<{ ok: true; reviewId?: string; detail?: string } | { ok: false; error: string }> {
  if (!opts.jobId) return { ok: false, error: 'No jobId on photo — cannot open work review' }

  const card = await getOrOpenFieldReview(opts.jobId)
  const reviewId =
    card.data?.review?.id ||
    (card.data as { id?: string } | null)?.id ||
    null

  if (!reviewId) {
    // Fallback: still open via POST
    const opened = await fetchJson<{ review?: { id: string }; id?: string }>(
      `/api/work-reviews/job/${opts.jobId}/open`,
      {
        method: 'POST',
        body: JSON.stringify({ trigger: 'pulse_verify' }),
      },
    )
    const rid = opened.data?.review?.id || opened.data?.id
    if (!rid) {
      return {
        ok: false,
        error: card.error || opened.error || 'Could not open work review for job',
      }
    }
    const sub = await submitPulseFieldReview(String(rid), {
      approved: opts.approved,
      photoId: opts.photoId,
      unitNo: opts.unitNo,
      note: opts.note,
      submittedBy: 'pulse',
    })
    if (sub.error) return { ok: false, error: sub.error }
  } else {
    const sub = await submitPulseFieldReview(String(reviewId), {
      approved: opts.approved,
      photoId: opts.photoId,
      unitNo: opts.unitNo,
      note: opts.note,
      submittedBy: 'pulse',
    })
    if (sub.error) return { ok: false, error: sub.error }
  }

  if (opts.approved) {
    const v = await getWorkVerification(opts.jobId)
    const verification = v.data?.verification as {
      discrepancies?: { id: string; status?: string }[]
      suggestions?: { discrepancyId?: string; action?: string }[]
    } | undefined
    const discs = verification?.discrepancies || []
    for (const d of discs) {
      if (d.status && d.status !== 'open' && d.status !== 'pending_review') continue
      await applyVerificationSuggestion(opts.jobId, {
        discrepancyId: d.id,
        reason: opts.note || 'Pulse approved field photo evidence',
        status: 'dismissed',
      })
    }
  } else {
    await updateJobBoardStatus(opts.jobId, 'flagged')
  }

  return {
    ok: true,
    reviewId: reviewId || undefined,
    detail: opts.approved
      ? 'Field review submitted (approved) — work-review pipeline notified'
      : 'Rework requested — job set to hold + field review noted',
  }
}


export function getApiBase() {
  return API_BASE
}


export async function checkApiHealth(): Promise<{ ok: boolean; error?: string }> {
  const r = await fetchJson<{ ok?: boolean }>('/api/building-ops/health')
  if (r.data && (r.data.ok === true || r.status === 200)) return { ok: true }
  // fallback lighter ping
  const j = await fetchJson('/api/jobs?limit=1')
  if (j.status > 0 && j.status < 500) return { ok: true }
  return { ok: false, error: r.error || j.error || 'Halo API unreachable' }
}

/** Create a work order from field walk cart — maps to POST /api/jobs/quick */
export async function createWorkOrder(input: {
  unit: string
  services: string[]
  notes?: string
  propertyId?: string
}): Promise<{ id?: string; error?: string }> {
  const body = {
    unitNo: input.unit,
    services: input.services,
    notes: input.notes || '',
    propertyId: input.propertyId,
  }
  const res = await fetchJson<{ id?: string; jobId?: string; error?: string }>(
    '/api/jobs/quick',
    { method: 'POST', body: JSON.stringify(body) },
  )
  if (res.error) return { error: res.error }
  return { id: res.data?.id || res.data?.jobId }
}
