/**
 * LiveMap — Mobbin-faithful Uber map + sheet + DoorDash filters + Airbnb cards
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { MapContainer, TileLayer, CircleMarker, Marker, useMap } from 'react-leaflet'
import L from 'leaflet'
import {
  Camera, MessageCircle, ShoppingBag, LayoutGrid, Map as MapIcon, X, Loader2,
} from 'lucide-react'
import {
  getPlate, getWorkItems, getRoleFromStorage, subscribePlate, getWorkVerification,
  updateJobBoardStatus, checkApiHealth, BOARD_COLUMNS,
  type Plate, type Role, type WorkItem, type Building,
} from '@/lib/api'
import { cn } from '@/lib/cn'
import { JobFacts } from '@/components/JobFacts'
import { JobRow } from '@/components/JobRow'
import { Sheet, type SheetSnap } from '@/components/Sheet'
import { PrimaryCTA } from '@/components/PrimaryCTA'
import { StatusChip } from '@/components/StatusChip'

function FitBounds({ buildings }: { buildings: Building[] }) {
  const map = useMap()
  useEffect(() => {
    if (!buildings.length) return
    const pts = buildings.filter((b) => b.lat && b.lng).map((b) => [b.lat, b.lng] as [number, number])
    if (pts.length === 1) map.setView(pts[0], 17)
    else if (pts.length > 1) map.fitBounds(L.latLngBounds(pts), { padding: [48, 48] })
  }, [buildings, map])
  return null
}

function unitPin(label: string, active: boolean) {
  return L.divIcon({
    className: 'halo-marker',
    html: `<div style="background:${active ? '#0A0F0C' : '#fff'};color:${active ? '#B4FF44' : '#0A0F0C'};border:2px solid #0A0F0C;border-radius:999px;padding:5px 11px;font:700 12px/1 Inter,system-ui,sans-serif;box-shadow:0 4px 14px rgba(0,0,0,.16);white-space:nowrap">${label}</div>`,
    iconSize: [1, 1],
    iconAnchor: [24, 14],
  })
}

export default function LiveMap() {
  const nav = useNavigate()
  const role = (getRoleFromStorage() || 'pulse') as Role
  const [plate, setPlate] = useState<Plate | null>(null)
  const [works, setWorks] = useState<WorkItem[]>([])
  const [loading, setLoading] = useState(true)
  const [dataError, setDataError] = useState<string | null>(null)
  const [apiOk, setApiOk] = useState<boolean | null>(null)
  const [mode, setMode] = useState<'map' | 'board'>('map')
  const [sheet, setSheet] = useState<SheetSnap>('half')
  const [selectedJob, setSelectedJob] = useState<WorkItem | null>(null)
  const [selectedBldg, setSelectedBldg] = useState<Building | null>(null)
  const [filter, setFilter] = useState<'all' | WorkItem['status']>('all')
  const [verify, setVerify] = useState<Record<string, unknown> | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    const health = await checkApiHealth()
    setApiOk(health.ok)
    const [p, w] = await Promise.all([getPlate(role), getWorkItems()])
    setPlate(p)
    setWorks(w.items)
    setDataError(
      (!health.ok ? health.error || 'Halo API unreachable' : null) || p.error || w.error || null,
    )
    setLoading(false)
  }, [role])

  useEffect(() => { load() }, [load])
  useEffect(() => {
    if (!plate?.propertyId) return
    return subscribePlate(plate.propertyId, () => load())
  }, [plate?.propertyId, load])

  const filtered = useMemo(
    () => (filter === 'all' ? works : works.filter((w) => w.status === filter)),
    [works, filter],
  )
  const center = plate?.center || ([33.0705, -96.751] as [number, number])

  async function openJob(job: WorkItem) {
    setSelectedJob(job)
    setSheet('half')
    if (role === 'vendor') {
      const v = await getWorkVerification(job.id)
      setVerify((v.data?.verification as Record<string, unknown>) || null)
    } else setVerify(null)
  }

  async function moveCard(job: WorkItem, next: WorkItem['status']) {
    const res = await updateJobBoardStatus(job.id, next)
    if (res.error) {
      setDataError(res.status === 409 ? `PO required to complete ${job.jobNo || job.unit}` : res.error)
      return
    }
    const raw = BOARD_COLUMNS.find((c) => c.key === next)?.haloStatus || next
    setWorks((prev) => prev.map((w) => (w.id === job.id ? { ...w, status: next, rawStatus: raw } : w)))
    if (selectedJob?.id === job.id) setSelectedJob({ ...job, status: next, rawStatus: raw })
  }

  const title = selectedJob
    ? `Unit ${selectedJob.unit}`
    : plate?.summary?.liveJobs != null
      ? `${plate.summary.liveJobs} jobs on site`
      : 'Choose a job'

  return (
    <div className="h-full relative overflow-hidden bg-[#E8EBE9] text-ink">
      {/* Floating chrome — Uber */}
      <div className="absolute top-0 inset-x-0 z-30 flex items-start gap-2 px-3 pt-[max(12px,env(safe-area-inset-top))] pointer-events-none">
        <button
          type="button"
          onClick={() => nav('/enter')}
          className="pointer-events-auto press h-11 w-11 rounded-full bg-white shadow-[0_2px_12px_rgba(0,0,0,0.12)] grid place-items-center text-[18px]"
        >
          ←
        </button>
        <div className="pointer-events-auto flex-1 flex justify-center pt-1">
          <div className="rounded-full bg-white shadow-[0_2px_12px_rgba(0,0,0,0.1)] px-4 py-2 flex items-center gap-2">
            <span className={cn('h-2 w-2 rounded-full', apiOk && plate?.live ? 'bg-lime live-dot' : apiOk === false ? 'bg-danger' : 'bg-black/25')} />
            <span className="text-[13px] font-semibold">Halo Live</span>
            <span className="text-[11px] text-[#6B6B6B] capitalize">{role}</span>
          </div>
        </div>
        <button
          type="button"
          onClick={() => setMode(mode === 'map' ? 'board' : 'map')}
          className="pointer-events-auto press h-11 w-11 rounded-full bg-white shadow-[0_2px_12px_rgba(0,0,0,0.12)] grid place-items-center"
        >
          {mode === 'map' ? <LayoutGrid className="h-5 w-5" /> : <MapIcon className="h-5 w-5" />}
        </button>
      </div>

      {apiOk === false && (
        <div className="absolute top-[4.5rem] inset-x-3 z-40 rounded-2xl bg-danger text-white text-[13px] font-medium px-4 py-3 flex justify-between gap-3 shadow-lg">
          <span>API down — wake archangel-halo</span>
          <button type="button" onClick={load} className="underline font-semibold">Retry</button>
        </div>
      )}

      {mode === 'map' && (
        <>
          <div className="absolute inset-0">
            {loading && !plate ? (
              <div className="h-full grid place-items-center"><Loader2 className="h-7 w-7 animate-spin text-[#6B6B6B]" /></div>
            ) : (
              <MapContainer center={center} zoom={16} className="h-full w-full" zoomControl={false} attributionControl={false}>
                <TileLayer url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png" />
                <FitBounds buildings={plate?.buildings || []} />
                {(plate?.buildings || []).map((b) => (
                  <CircleMarker
                    key={b.id}
                    center={[b.lat, b.lng]}
                    radius={selectedBldg?.id === b.id ? 11 : 8}
                    pathOptions={{
                      color: '#0A0F0C',
                      fillColor: selectedBldg?.id === b.id ? '#B4FF44' : '#0A0F0C',
                      fillOpacity: 0.9,
                      weight: 2,
                    }}
                    eventHandlers={{
                      click: () => { setSelectedBldg(b); setSelectedJob(null); setSheet('half') },
                    }}
                  />
                ))}
                {filtered.map((w) => {
                  const b = (plate?.buildings || []).find((x) => x.id === w.buildingId)
                  if (!b) return null
                  return (
                    <Marker
                      key={w.id}
                      position={[b.lat, b.lng]}
                      icon={unitPin(`Unit ${w.unit}`, selectedJob?.id === w.id)}
                      eventHandlers={{ click: () => openJob(w) }}
                    />
                  )
                })}
                {(plate?.crew || []).map((c) =>
                  c.lat && c.lng ? (
                    <CircleMarker
                      key={c.id}
                      center={[c.lat, c.lng]}
                      radius={6}
                      pathOptions={{ color: '#fff', fillColor: '#B4FF44', fillOpacity: 1, weight: 2 }}
                    />
                  ) : null,
                )}
              </MapContainer>
            )}
          </div>

          {/* Live crew strip */}
          {(plate?.crew || []).length > 0 && !selectedJob && (
            <div className="absolute left-3 right-3 z-20 flex items-center gap-2 overflow-x-auto no-scrollbar"
              style={{ top: 'max(12px, env(safe-area-inset-top))' }}>
              <div className="shrink-0 rounded-full bg-ink/90 text-live text-[11px] mono font-semibold px-3 py-1.5 border border-live/30">
                {(plate?.crew || []).length} crew GPS
              </div>
              {(plate?.crew || []).slice(0, 4).map((c) => (
                <div key={c.id} className="shrink-0 rounded-full bg-ink/90 text-white text-[11px] font-medium px-3 py-1.5 border border-white/10">
                  {c.name}
                </div>
              ))}
            </div>
          )}

          {/* Airbnb horizontal cards */}
          {!selectedJob && filtered.length > 0 && sheet !== 'full' && (
            <div
              className="absolute left-0 right-0 z-20 overflow-x-auto no-scrollbar"
              style={{ bottom: sheet === 'peek' ? '28vh' : '52vh' }}
            >
              <div className="flex gap-3 px-4" style={{ width: 'max-content' }}>
                {filtered.slice(0, 10).map((w) => (
                  <button
                    key={w.id}
                    type="button"
                    onClick={() => openJob(w)}
                    className="press w-[272px] rounded-2xl bg-white shadow-[0_8px_28px_rgba(0,0,0,0.14)] border border-black/[0.04] p-3.5 text-left"
                  >
                    <div className="flex justify-between items-start gap-2 mb-1.5">
                      <span className="font-bold text-[15px] tabular-nums">Unit {w.unit}</span>
                      <StatusChip status={w.status} />
                    </div>
                    <div className="text-[13px] font-medium line-clamp-2 text-ink">
                      {w.services?.length ? w.services.join(' · ') : w.title}
                    </div>
                    <div className="mt-1 text-[12px] text-[#6B6B6B]">
                      {w.assignedTo || 'Unassigned'}
                    </div>
                  </button>
                ))}
              </div>
            </div>
          )}

          <Sheet snap={sheet} onSnapChange={setSheet}>
            <div className="px-5 pb-1">
              <h1 className="text-[22px] font-bold tracking-tight">{title}</h1>
              {dataError && <p className="text-[12px] text-danger mt-1">{dataError}</p>}
            </div>

            {/* DoorDash filter chips */}
            <div className="px-4 py-2 flex gap-2 overflow-x-auto no-scrollbar">
              {(['all', 'open', 'in_progress', 'review', 'approved', 'flagged'] as const).map((f) => (
                <button
                  key={f}
                  type="button"
                  onClick={() => setFilter(f)}
                  className={cn(
                    'press shrink-0 rounded-full px-3.5 py-[7px] text-[13px] font-semibold border',
                    filter === f ? 'bg-ink text-white border-ink' : 'bg-white text-ink border-black/10',
                  )}
                >
                  {f === 'all' ? 'All' : f === 'in_progress' ? 'Active' : f[0].toUpperCase() + f.slice(1)}
                </button>
              ))}
            </div>

            <div className="flex-1 overflow-y-auto px-2 pb-28">
              {selectedJob ? (
                <div className="px-3 space-y-4 pt-1">
                  <div className="flex justify-between items-start">
                    <JobFacts job={selectedJob} />
                    <button type="button" onClick={() => setSelectedJob(null)} className="press h-8 w-8 rounded-full bg-black/5 grid place-items-center">
                      <X className="h-4 w-4" />
                    </button>
                  </div>
                  <div className="flex flex-wrap gap-2">
                    {BOARD_COLUMNS.map((c) => (
                      <button
                        key={c.key}
                        type="button"
                        onClick={() => moveCard(selectedJob, c.key)}
                        className={cn(
                          'press rounded-full px-3 py-1.5 text-[12px] font-semibold border',
                          selectedJob.status === c.key ? 'bg-ink text-white border-ink' : 'border-black/10',
                        )}
                      >
                        {c.label}
                      </button>
                    ))}
                  </div>
                  {verify && (
                    <p className="text-[12px] text-[#6B6B6B]">
                      Verification loaded · {Object.keys(verify).length} fields
                    </p>
                  )}
                  <div className="flex gap-2">
                    <Link to={`/field/${selectedJob.id}`} className="flex-1">
                      <PrimaryCTA>Open field check-in</PrimaryCTA>
                    </Link>
                    <Link to="/messages" className="press h-[52px] w-[52px] rounded-full border border-black/10 grid place-items-center">
                      <MessageCircle className="h-5 w-5" />
                    </Link>
                  </div>
                </div>
              ) : (
                <div className="space-y-0.5">
                  {filtered.map((w) => (
                    <JobRow
                      key={w.id}
                      job={w}
                      selected={selectedJob?.id === w.id}
                      onClick={() => openJob(w)}
                    />
                  ))}
                  {!loading && !filtered.length && (
                    <p className="text-center text-[#6B6B6B] py-12 text-[15px]">No jobs on this filter</p>
                  )}
                </div>
              )}
            </div>

            {/* Sticky Uber CTA bar */}
            <div className="absolute inset-x-0 bottom-0 px-4 pt-6 pb-[max(12px,env(safe-area-inset-bottom))] bg-gradient-to-t from-white via-white to-transparent">
              <div className="flex gap-2 items-center">
                <Link to={role === 'pulse' ? '/approve' : '/order'} className="flex-1">
                  <PrimaryCTA>Request work</PrimaryCTA>
                </Link>
                <Link
                  to={role === 'vendor' ? '/field' : '/verify'}
                  className="press h-[52px] w-[52px] shrink-0 rounded-full border border-black/10 bg-white grid place-items-center"
                >
                  <Camera className="h-5 w-5" />
                </Link>
              </div>
            </div>
          </Sheet>
        </>
      )}

      {mode === 'board' && (
        <div className="absolute inset-0 pt-16 px-3 pb-6 overflow-x-auto">
          <div className="flex gap-3 h-full min-w-max">
            {BOARD_COLUMNS.map((col) => (
              <div key={col.key} className="w-[300px] flex flex-col rounded-2xl bg-white shadow-sm border border-black/[0.05]">
                <div className="px-4 py-3 border-b border-black/[0.05] flex justify-between">
                  <span className="font-semibold text-[14px]">{col.label}</span>
                  <span className="text-[12px] text-[#6B6B6B]">{works.filter((w) => w.status === col.key).length}</span>
                </div>
                <div className="flex-1 overflow-y-auto p-2 space-y-1">
                  {works.filter((w) => w.status === col.key).map((w) => (
                    <div key={w.id} className="rounded-xl border border-black/[0.05] overflow-hidden">
                      <JobRow job={w} onClick={() => openJob(w)} />
                      <div className="px-3 pb-2 flex flex-wrap gap-1">
                        {BOARD_COLUMNS.filter((c) => c.key !== col.key).slice(0, 3).map((c) => (
                          <button
                            key={c.key}
                            type="button"
                            onClick={() => moveCard(w, c.key)}
                            className="press text-[10px] font-semibold px-2 py-1 rounded-full border border-black/10"
                          >
                            → {c.label}
                          </button>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
          <div className="fixed bottom-4 inset-x-4 flex gap-2 md:hidden">
            <Link to="/order" className="flex-1"><PrimaryCTA>Request work</PrimaryCTA></Link>
            <button type="button" onClick={() => setMode('map')} className="press h-[52px] px-4 rounded-full bg-white border border-black/10 font-semibold text-[14px]">Map</button>
          </div>
        </div>
      )}
    </div>
  )
}
