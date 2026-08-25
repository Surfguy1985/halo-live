/**
 * Turo-style photo check-in companion — wired to the SAME Halo endpoints
 * the Base44 field / paycard app uses:
 *
 *   GET  /api/checkin/:token
 *   POST /api/checkin/:token/checkin   { unitNo, lat, lng, accuracy }
 *   POST /api/storage/uploads/request-url
 *   PUT  uploadURL (bytes)
 *   POST /api/checkin/:token/photos   { storagePath, phase: before|after }
 *   POST /api/checkin/:token/checkout { lat, lng, accuracy }
 *
 * Photos land in crew_photos → Base44-mirrored activity → plate.photoBillboards
 */

const API_BASE = (import.meta.env.VITE_API_BASE as string | undefined)?.replace(/\/$/, '') ?? ''
const TOKEN_KEY = 'halo-field-checkin-token'

export function getStoredFieldToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY) || (import.meta.env.VITE_FIELD_CHECKIN_TOKEN as string) || null
  } catch {
    return (import.meta.env.VITE_FIELD_CHECKIN_TOKEN as string) || null
  }
}

export function setStoredFieldToken(token: string) {
  localStorage.setItem(TOKEN_KEY, token.trim())
}

export function clearStoredFieldToken() {
  localStorage.removeItem(TOKEN_KEY)
}

async function api<T>(path: string, init?: RequestInit): Promise<{ ok: true; data: T } | { ok: false; status: number; error: string; code?: string }> {
  try {
    const res = await fetch(`${API_BASE}${path}`, {
      ...init,
      headers: {
        Accept: 'application/json',
        ...(init?.body ? { 'Content-Type': 'application/json' } : {}),
        ...init?.headers,
      },
    })
    const text = await res.text()
    let data: unknown = null
    try {
      data = text ? JSON.parse(text) : null
    } catch {
      data = { error: text }
    }
    if (!res.ok) {
      const err = data as { error?: string; code?: string; message?: string }
      return {
        ok: false,
        status: res.status,
        error: err?.error || err?.message || res.statusText,
        code: err?.code,
      }
    }
    return { ok: true, data: data as T }
  } catch (e) {
    return { ok: false, status: 0, error: String((e as Error)?.message || e) }
  }
}

export interface CheckinSession {
  crew: { id: string; name: string; isForeman?: boolean }
  todayAssignment: {
    propertyName?: string
    unitLabel?: string
    jobDescription?: string
    units?: string[]
    jobIds?: string[]
  } | null
  currentStatus: string
  lastCheckin?: string | null
  photos?: {
    before: { id: string; phase: string; url: string }[]
    after: { id: string; phase: string; url: string }[]
  } | null
  pay?: { mustCompleteToGetPaid: boolean; steps: string[] }
  session?: unknown
}

export async function loadCheckinSession(token: string) {
  return api<CheckinSession>(`/api/checkin/${encodeURIComponent(token)}`)
}

export interface GpsFix {
  lat: number
  lng: number
  accuracy?: number
}

export function getGps(): Promise<GpsFix> {
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error('Location not available on this device'))
      return
    }
    navigator.geolocation.getCurrentPosition(
      (pos) =>
        resolve({
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
          accuracy: pos.coords.accuracy,
        }),
      (err) => reject(new Error(err.message || 'GPS denied')),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 10000 },
    )
  })
}

export async function fieldCheckin(
  token: string,
  unitNo: string,
  gps: GpsFix,
) {
  return api<{ ok: boolean; checkedIn?: boolean; jobId?: string }>(
    `/api/checkin/${encodeURIComponent(token)}/checkin`,
    {
      method: 'POST',
      body: JSON.stringify({
        unitNo,
        unitLabel: unitNo,
        lat: gps.lat,
        lng: gps.lng,
        accuracy: gps.accuracy,
      }),
    },
  )
}

export async function fieldCheckout(token: string, gps: GpsFix) {
  return api<{ ok: boolean; checkedOut?: boolean }>(
    `/api/checkin/${encodeURIComponent(token)}/checkout`,
    {
      method: 'POST',
      body: JSON.stringify({
        lat: gps.lat,
        lng: gps.lng,
        accuracy: gps.accuracy,
      }),
    },
  )
}

/** Presign → PUT bytes → register photo on check-in session (Base44 field path) */
export async function uploadFieldPhoto(
  token: string,
  file: Blob,
  phase: 'before' | 'after',
  note?: string,
): Promise<{ ok: true; photo: { id: string; phase: string; url: string } } | { ok: false; error: string }> {
  const name = `field-${phase}-${Date.now()}.jpg`
  const contentType = file.type || 'image/jpeg'
  const size = file.size

  const presign = await api<{ uploadURL: string; objectPath: string }>(
    '/api/storage/uploads/request-url',
    {
      method: 'POST',
      body: JSON.stringify({ name, size, contentType }),
    },
  )
  if (!presign.ok) {
    return { ok: false, error: presign.error || 'Could not start upload' }
  }

  const { uploadURL, objectPath } = presign.data
  try {
    const put = await fetch(uploadURL, {
      method: 'PUT',
      body: file,
      headers: { 'Content-Type': contentType },
    })
    if (!put.ok) {
      return { ok: false, error: `Upload failed (${put.status})` }
    }
  } catch (e) {
    return { ok: false, error: String((e as Error)?.message || e) }
  }

  const reg = await api<{
    ok: boolean
    photo?: { id: string; phase: string; url: string }
  }>(`/api/checkin/${encodeURIComponent(token)}/photos`, {
    method: 'POST',
    body: JSON.stringify({
      storagePath: objectPath,
      phase,
      note: note || undefined,
    }),
  })

  if (!reg.ok || !reg.data.photo) {
    return { ok: false, error: !reg.ok ? reg.error : 'Photo not registered' }
  }

  // Normalize URL through our proxy base
  const url = reg.data.photo.url.startsWith('http')
    ? reg.data.photo.url
    : `${API_BASE}${reg.data.photo.url}`

  return {
    ok: true,
    photo: { ...reg.data.photo, url },
  }
}

export function phaseForStep(title: string, order: number, total: number): 'before' | 'after' {
  // First half of guide = before, second half = after (matches Base44 before/after gate)
  if (title.toLowerCase().includes('before')) return 'before'
  if (title.toLowerCase().includes('after')) return 'after'
  return order <= Math.ceil(total / 2) ? 'before' : 'after'
}
