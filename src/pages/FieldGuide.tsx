/**
 * FieldGuide — Turo-style photo check-in (Mobbin patterns)
 * Intro checklist → zone diagram → one area → progress → submit
 * Wired to Halo /api/checkin/:token + jobs list
 */
import { useEffect, useMemo, useRef, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { ArrowLeft, Camera, Check, Loader2, MapPin, HelpCircle } from 'lucide-react'
import {
  getWorkItems, getRoleFromStorage, FIELD_GUIDES, photoUrl,
  type WorkItem, type PhotoStep,
} from '@/lib/api'
import {
  getStoredFieldToken, loadCheckinSession, uploadFieldPhoto, phaseForStep,
  fieldCheckout, getGps, type CheckinSession,
} from '@/lib/fieldCompanion'
import { cn } from '@/lib/cn'
import { StatusChip } from '@/components/StatusChip'

type Phase = 'pick' | 'intro' | 'zone' | 'done'

const ZONE_HINTS: Record<string, string> = {
  turn_clean: 'Walk every room. Capture before and after each zone.',
  make_ready: 'Document damage, repairs, and final condition.',
  carpet: 'Wide shot of each room + close-ups of stains.',
  paint: 'Walls, trim, and touch-up areas before and after.',
  punch: 'Each punch item — before work and after complete.',
}

export default function FieldGuide() {
  const { workId } = useParams()
  const nav = useNavigate()
  const fileRef = useRef<HTMLInputElement>(null)
  const [jobs, setJobs] = useState<WorkItem[]>([])
  const [job, setJob] = useState<WorkItem | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [phase, setPhase] = useState<Phase>('pick')
  const [stepIdx, setStepIdx] = useState(0)
  const [captured, setCaptured] = useState<Record<string, string[]>>({})
  const [busy, setBusy] = useState(false)
  const [session, setSession] = useState<CheckinSession | null>(null)
  const token = getStoredFieldToken()

  useEffect(() => {
    ;(async () => {
      setLoading(true)
      const { items, error: err } = await getWorkItems()
      setJobs(items)
      setError(err || null)
      if (token) {
        const s = await loadCheckinSession(token)
        if (s.ok) setSession(s.data)
      }
      if (workId) {
        const found = items.find((j) => j.id === workId)
        if (found) {
          setJob(found)
          setPhase('intro')
        }
      }
      setLoading(false)
    })()
  }, [workId, token])

  const steps: PhotoStep[] = useMemo(() => {
    if (!job) return []
    return FIELD_GUIDES[job.type] || FIELD_GUIDES.turn_clean
  }, [job])

  const step = steps[stepIdx]
  const progress = steps.length ? Math.round((stepIdx / steps.length) * 100) : 0
  const doneCount = Object.values(captured).reduce((n, a) => n + a.length, 0)

  async function onFilePicked(file: File | null) {
    if (!file || !job || !step) return
    setBusy(true)
    setError(null)
    const phasePhoto = phaseForStep(step.title, step.order, steps.length)
    if (token) {
      const r = await uploadFieldPhoto(token, file, phasePhoto, step.title)
      if (!r.ok) {
        setError(r.error)
        // still keep local preview so crew can continue
        const local = URL.createObjectURL(file)
        setCaptured((c) => ({ ...c, [step.id]: [...(c[step.id] || []), local] }))
        setBusy(false)
        return
      }
      setCaptured((c) => ({
        ...c,
        [step.id]: [...(c[step.id] || []), r.photo.url],
      }))
    } else {
      const local = URL.createObjectURL(file)
      setCaptured((c) => ({ ...c, [step.id]: [...(c[step.id] || []), local] }))
      setError('No check-in token — photo kept locally. Set token or open from Base44 paycard link.')
    }
    setBusy(false)
  }

  function nextZone() {
    if (stepIdx < steps.length - 1) setStepIdx((i) => i + 1)
    else setPhase('done')
  }

  async function finish() {
    setBusy(true)
    if (token) {
      try {
        const gps = await getGps()
        const r = await fieldCheckout(token, gps)
        if (!r.ok) setError(r.error)
      } catch {
        /* gps optional */
      }
    }
    setBusy(false)
  }

  // ── Pick ──────────────────────────────────────────────
  if (phase === 'pick' || (!job && !loading)) {
    return (
      <div className="min-h-full bg-white text-ink page-enter max-w-lg mx-auto">
        <header className="sticky top-0 z-10 flex h-14 items-center gap-3 px-3 border-b border-black/[0.06] bg-white">
          <Link to="/live" className="press grid h-10 w-10 place-items-center rounded-full hover:bg-black/[0.04]">
            <ArrowLeft className="h-5 w-5" />
          </Link>
          <div className="flex-1">
            <div className="text-[17px] font-semibold">Field check-in</div>
            <div className="text-[11px] text-slate-dim">
              {token ? 'Token linked · Base44 path' : 'Turo-style photo guide'}
            </div>
          </div>
          <HelpCircle className="h-5 w-5 text-slate-dim" />
        </header>
        <main className="px-4 py-5 space-y-3">
          {loading && (
            <div className="flex justify-center py-16">
              <Loader2 className="h-6 w-6 animate-spin text-slate-dim" />
            </div>
          )}
          {error && <p className="text-sm text-danger">{error}</p>}
          {!loading && !jobs.length && (
            <p className="text-center text-slate-dim py-16">No live jobs to check in</p>
          )}
          {jobs.map((w) => (
            <button
              key={w.id}
              type="button"
              onClick={() => {
                setJob(w)
                setPhase('intro')
                setStepIdx(0)
                setCaptured({})
                setError(null)
              }}
              className="press w-full text-left rounded-2xl border border-black/[0.08] bg-white p-4 shadow-sm"
            >
              <div className="flex justify-between gap-2 mb-2">
                <span className="font-bold text-[16px] tabular-nums">Unit {w.unit}</span>
                <StatusChip status={w.status} />
              </div>
              <div className="text-[14px] font-medium line-clamp-2">
                {w.services?.length ? w.services.join(' · ') : w.title}
              </div>
              <div className="mt-1.5 text-[12px] text-slate-dim">
                {w.assignedTo ? `Crew: ${w.assignedTo}` : 'Unassigned'}
                {w.jobNo ? ` · ${w.jobNo}` : ''}
              </div>
            </button>
          ))}
        </main>
      </div>
    )
  }

  // ── Intro ─────────────────────────────────────────────
  if (phase === 'intro' && job) {
    return (
      <div className="min-h-full bg-white text-ink page-enter max-w-lg mx-auto flex flex-col">
        <header className="flex h-14 items-center justify-between px-4">
          <button
            type="button"
            onClick={() => {
              setPhase('pick')
              setJob(null)
            }}
            className="press grid h-10 w-10 place-items-center rounded-full hover:bg-black/[0.04]"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
          <span className="text-[13px] text-slate-dim font-medium">Help</span>
        </header>
        <div className="flex-1 px-6 pt-4 pb-8 flex flex-col">
          <div className="flex-1 flex flex-col items-center text-center">
            <div className="w-full max-w-xs aspect-square rounded-[32px] bg-[#F4F4F5] flex items-center justify-center mb-8">
              <Camera className="h-16 w-16 text-ink/30" strokeWidth={1.25} />
            </div>
            <h1 className="text-[28px] font-bold tracking-tight">Let&apos;s check in</h1>
            <p className="mt-3 text-[15px] text-slate-dim leading-relaxed max-w-sm">
              Complete photo steps for{' '}
              <span className="text-ink font-semibold">Unit {job.unit}</span> before marking work
              done. Progress is saved as you go.
            </p>
            <ul className="mt-8 w-full text-left space-y-4">
              <li className="flex gap-3 items-start">
                <MapPin className="h-5 w-5 text-ink shrink-0 mt-0.5" />
                <div>
                  <div className="font-semibold text-[15px]">Confirm unit & services</div>
                  <div className="text-[13px] text-slate-dim">
                    {job.services?.length ? job.services.join(' · ') : job.title}
                  </div>
                </div>
              </li>
              <li className="flex gap-3 items-start">
                <Camera className="h-5 w-5 text-ink shrink-0 mt-0.5" />
                <div>
                  <div className="font-semibold text-[15px]">Take zone photos</div>
                  <div className="text-[13px] text-slate-dim">
                    {ZONE_HINTS[job.type] || ZONE_HINTS.turn_clean}
                  </div>
                </div>
              </li>
              <li className="flex gap-3 items-start">
                <Check className="h-5 w-5 text-ink shrink-0 mt-0.5" />
                <div>
                  <div className="font-semibold text-[15px]">Submit check-in</div>
                  <div className="text-[13px] text-slate-dim">Photos push to Halo plate & Base44</div>
                </div>
              </li>
            </ul>
            <div className="mt-6 w-full rounded-2xl bg-[#F0F7E8] border border-lime/30 px-4 py-3 text-[13px] text-ink text-left">
              Crew: <span className="font-semibold">{job.assignedTo || 'Unassigned'}</span>
              {job.jobNo ? ` · ${job.jobNo}` : ''}
              {session?.crew?.name ? ` · Signed in as ${session.crew.name}` : ''}
            </div>
          </div>
          <button
            type="button"
            onClick={() => setPhase('zone')}
            className="press w-full rounded-full bg-ink text-white font-semibold py-4 text-[16px] mt-6"
          >
            Continue
          </button>
        </div>
      </div>
    )
  }

  // ── Zone ──────────────────────────────────────────────
  if (phase === 'zone' && job && step) {
    const stepPhotos = captured[step.id] || []
    return (
      <div className="min-h-full bg-white text-ink page-enter max-w-lg mx-auto flex flex-col">
        <header className="flex h-14 items-center justify-between px-4">
          <button
            type="button"
            onClick={() => (stepIdx === 0 ? setPhase('intro') : setStepIdx((i) => i - 1))}
            className="press grid h-10 w-10 place-items-center rounded-full hover:bg-black/[0.04]"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
          <div className="text-[13px] font-medium text-slate-dim">
            {stepIdx + 1} of {steps.length}
          </div>
          <span className="text-[13px] text-slate-dim">Help</span>
        </header>

        <div className="h-1 bg-black/[0.06]">
          <div className="h-full bg-lime transition-all duration-300" style={{ width: `${progress}%` }} />
        </div>

        <div className="flex-1 px-6 pt-8 pb-8 flex flex-col">
          <div className="flex-1 flex flex-col items-center text-center">
            <div className="w-full max-w-xs aspect-[4/3] rounded-[28px] bg-[#F4F4F5] flex items-center justify-center mb-6 relative overflow-hidden">
              {stepPhotos[0] ? (
                <img src={stepPhotos[0]} alt="" className="absolute inset-0 w-full h-full object-cover" />
              ) : (
                <Camera className="h-14 w-14 text-ink/25" strokeWidth={1.25} />
              )}
            </div>
            <h1 className="text-[24px] font-bold tracking-tight">{step.title}</h1>
            <p className="mt-2 text-[15px] text-slate-dim leading-relaxed max-w-sm">
              {step.instruction}
              {step.tip ? ` ${step.tip}.` : ''}
            </p>
            {stepPhotos.length > 0 && (
              <p className="mt-3 text-[13px] font-semibold text-ink">
                {stepPhotos.length} photo{stepPhotos.length > 1 ? 's' : ''} added
              </p>
            )}
            {error && <p className="mt-2 text-sm text-danger">{error}</p>}
          </div>

          <input
            ref={fileRef}
            type="file"
            accept="image/*"
            capture="environment"
            className="hidden"
            onChange={(e) => onFilePicked(e.target.files?.[0] || null)}
          />

          <div className="space-y-3 mt-6">
            <button
              type="button"
              disabled={busy}
              onClick={() => fileRef.current?.click()}
              className="press w-full rounded-full bg-ink text-white font-semibold py-4 text-[16px] flex items-center justify-center gap-2 disabled:opacity-50"
            >
              {busy ? <Loader2 className="h-5 w-5 animate-spin" /> : <Camera className="h-5 w-5" />}
              {stepPhotos.length ? 'Add another photo' : 'Add photos'}
            </button>
            <button
              type="button"
              onClick={nextZone}
              className="press w-full rounded-full border border-black/10 font-semibold py-3.5 text-[15px]"
            >
              {stepIdx < steps.length - 1 ? 'Save and continue' : 'Finish zones'}
            </button>
            <button type="button" onClick={nextZone} className="press w-full text-[15px] font-medium text-slate-dim py-2">
              Skip
            </button>
          </div>
        </div>
      </div>
    )
  }

  // ── Done ──────────────────────────────────────────────
  return (
    <div className="min-h-full bg-white text-ink page-enter max-w-lg mx-auto flex flex-col">
      <header className="flex h-14 items-center px-4">
        <button
          type="button"
          onClick={() => nav('/live')}
          className="press grid h-10 w-10 place-items-center rounded-full hover:bg-black/[0.04]"
        >
          <ArrowLeft className="h-5 w-5" />
        </button>
      </header>
      <div className="flex-1 px-6 flex flex-col items-center text-center pt-10">
        <div className="h-20 w-20 rounded-full bg-lime/20 flex items-center justify-center mb-6">
          <Check className="h-10 w-10 text-ink" strokeWidth={2.5} />
        </div>
        <h1 className="text-[28px] font-bold tracking-tight">Check-in complete</h1>
        <p className="mt-3 text-[15px] text-slate-dim max-w-sm">
          {doneCount} photo{doneCount === 1 ? '' : 's'} for Unit {job?.unit}. Evidence lands on the
          Halo plate for Pulse and office.
        </p>
        {error && <p className="mt-2 text-sm text-danger">{error}</p>}
        <button
          type="button"
          disabled={busy}
          onClick={async () => {
            await finish()
            nav('/live')
          }}
          className="press mt-10 w-full rounded-full bg-ink text-white font-semibold py-4 text-[16px]"
        >
          {busy ? 'Submitting…' : 'Done — back to map'}
        </button>
        <Link to="/live" className="press mt-3 text-[15px] font-medium text-slate-dim py-2">
          Skip submit
        </Link>
      </div>
    </div>
  )
}
