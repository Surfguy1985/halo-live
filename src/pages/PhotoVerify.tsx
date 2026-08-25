/**
 * Pulse photo verify → real work-review pipeline
 * Approve: open field review → field-submit confirmAccurate → clear open discrepancies
 * Rework: field-submit rework + PATCH job hold
 */
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowLeft, Check, Loader2, RefreshCw, X } from 'lucide-react'
import {
  getPlate, getWorkItems, getRoleFromStorage, pulsePhotoDecision, photoUrl,
  type FieldPhoto, type WorkItem, type Role,
} from '@/lib/api'
import { cn } from '@/lib/cn'

export default function PhotoVerify() {
  const role = (getRoleFromStorage() || 'pulse') as Role
  const [photos, setPhotos] = useState<FieldPhoto[]>([])
  const [jobs, setJobs] = useState<WorkItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)
  const [done, setDone] = useState<Record<string, { verdict: 'approved' | 'rework'; detail?: string }>>({})

  async function load() {
    setLoading(true)
    const [plate, work] = await Promise.all([getPlate(role), getWorkItems()])
    setPhotos(plate.photos)
    setJobs(work.items)
    setError(plate.error || work.error || null)
    setLoading(false)
  }

  useEffect(() => {
    load()
  }, [role])

  async function decide(photo: FieldPhoto, approved: boolean) {
    const jobId = photo.jobId || jobs.find((j) => j.unit === photo.unitNo)?.id || jobs[0]?.id
    if (!jobId) {
      setError('No job linked to this photo — open a job on the plate first')
      return
    }
    setBusyId(photo.id)
    setError(null)
    const res = await pulsePhotoDecision({
      jobId,
      approved,
      photoId: photo.id,
      unitNo: photo.unitNo,
      note: approved
        ? `Pulse approved field photo ${photo.phase || ''}`.trim()
        : `Pulse requested rework on ${photo.phase || 'photo'} — retake required`,
    })
    setBusyId(null)
    if (!res.ok) {
      setError(res.error)
      return
    }
    setDone((d) => ({
      ...d,
      [photo.id]: {
        verdict: approved ? 'approved' : 'rework',
        detail: res.detail,
      },
    }))
  }

  return (
    <div className="min-h-full bg-white text-ink page-enter max-w-lg mx-auto">
      <header className="sticky top-0 z-20 flex h-14 items-center gap-3 border-b border-black/[0.06] px-3 bg-white">
        <Link to="/live" className="press grid h-10 w-10 place-items-center rounded-full hover:bg-black/[0.04]">
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <div className="flex-1 min-w-0">
          <div className="text-[17px] font-semibold">Photo verify</div>
          <div className="text-[11px] text-slate-dim">Pulse · work-review pipeline</div>
        </div>
        <button type="button" onClick={load} className="press grid h-9 w-9 place-items-center rounded-full hover:bg-black/[0.04]">
          <RefreshCw className={cn('h-4 w-4', loading && 'animate-spin')} />
        </button>
      </header>

      <main className="px-4 py-5 space-y-4">
        <p className="text-[13px] text-slate-dim leading-relaxed">
          Approve submits a field review to Halo (Money Lock path). Rework holds the job and flags the review.
        </p>
        {error && <p className="text-sm text-danger">{error}</p>}
        {loading && (
          <div className="flex justify-center py-16 text-slate-dim">
            <Loader2 className="h-6 w-6 animate-spin" />
          </div>
        )}
        {!loading && !photos.length && (
          <p className="text-center text-slate-dim py-16 text-[15px]">
            No field photos on the live plate yet
          </p>
        )}
        {photos.map((p) => {
          const result = done[p.id]
          const linkedJob = p.jobId || jobs.find((j) => j.unit === p.unitNo)?.id
          return (
            <article key={p.id} className="rounded-2xl border border-black/[0.08] overflow-hidden">
              <div className="aspect-[4/3] bg-[#F0F0F0]">
                <img
                  src={p.url.startsWith('http') || p.url.startsWith('/') ? p.url : photoUrl(p.url) || p.url}
                  alt=""
                  className="h-full w-full object-cover"
                />
              </div>
              <div className="p-3">
                <div className="flex justify-between text-[13px] text-slate-dim">
                  <span className="font-semibold text-ink capitalize">{p.phase || 'photo'}</span>
                  <span>
                    {p.unitNo ? `Unit ${p.unitNo}` : ''}
                    {linkedJob ? ' · job linked' : ' · no jobId'}
                  </span>
                </div>
                {result ? (
                  <div className="mt-3">
                    <p
                      className={cn(
                        'text-[14px] font-semibold',
                        result.verdict === 'approved' ? 'text-ink' : 'text-danger',
                      )}
                    >
                      {result.verdict === 'approved' ? 'Approved' : 'Rework requested'}
                    </p>
                    {result.detail && (
                      <p className="text-[12px] text-slate-dim mt-1">{result.detail}</p>
                    )}
                  </div>
                ) : (
                  <div className="mt-3 flex gap-2">
                    <button
                      type="button"
                      disabled={!!busyId || !linkedJob}
                      onClick={() => decide(p, true)}
                      className="press flex-1 rounded-full bg-lime text-ink font-semibold py-2.5 text-[14px] flex items-center justify-center gap-1.5 disabled:opacity-40"
                    >
                      {busyId === p.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                      Approve
                    </button>
                    <button
                      type="button"
                      disabled={!!busyId || !linkedJob}
                      onClick={() => decide(p, false)}
                      className="press flex-1 rounded-full border border-black/12 font-semibold py-2.5 text-[14px] flex items-center justify-center gap-1.5 disabled:opacity-40"
                    >
                      <X className="h-4 w-4" /> Rework
                    </button>
                  </div>
                )}
              </div>
            </article>
          )
        })}
      </main>
    </div>
  )
}
