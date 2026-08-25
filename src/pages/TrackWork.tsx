/**
 * B5 · Live tracking — map + Service ETA stack (hero)
 * Cure bands: shimmer + countdown, never spinner
 */
import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { MapContainer, TileLayer, CircleMarker, Marker } from 'react-leaflet'
import L from 'leaflet'
import { ArrowLeft, Phone, MessageCircle, ChevronDown, ChevronUp } from 'lucide-react'
import { ServiceEtaStack, type EtaDay } from '@/components/ServiceEtaStack'
import { formatMoney } from '@/lib/catalog'
import { cn } from '@/lib/cn'
import { loadSharedOrder } from '@/lib/orderBus'
import { etaDaysFromLines, etaSummary } from '@/lib/etaFromOrder'
import { getWorkItems } from '@/lib/api'

const CENTER: [number, number] = [33.0705, -96.751]

const DAYS: EtaDay[] = [
  {
    label: 'Today · Mon Aug 24',
    rows: [
      {
        kind: 'done',
        id: 'tub',
        title: 'Garden Tub Resurface',
        crew: 'Marco R',
        detail: 'Sprayed 7:40 AM · done',
      },
      {
        kind: 'cure',
        id: 'cure-tub',
        scale: 'long',
        title: 'Unit closed — curing',
        remaining: '19h 42m',
        reopens: '7:40 AM tomorrow',
        reason: 'The tub is drying',
      },
    ],
  },
  {
    label: 'Tomorrow · Tue Aug 25',
    rows: [
      {
        kind: 'waiting',
        id: 'paint',
        title: 'Wall Prep & Paint',
        crew: 'Jose M',
        after: 'tub cures',
      },
      {
        kind: 'cure',
        id: 'cure-paint',
        scale: 'short',
        title: 'Paint set',
        remaining: '3h',
        reopens: '2:40 PM',
        reason: 'paint sets',
      },
      {
        kind: 'waiting',
        id: 'carpet',
        title: 'Carpet Clean',
        crew: 'Kaynne T',
        after: 'paint sets',
      },
      {
        kind: 'waiting',
        id: 'clean',
        title: 'Vacant Unit Clean',
        crew: 'Kaynne T',
        after: 'carpet dry',
      },
      {
        kind: 'waiting',
        id: 'walk',
        title: 'Final walk',
        after: 'clean complete',
      },
    ],
  },
]

function unitPin() {
  return L.divIcon({
    className: 'halo-marker',
    html: `<div style="width:18px;height:18px;background:#080D1A;border:3px solid #fff;border-radius:50% 50% 50% 0;transform:rotate(-45deg);box-shadow:0 2px 8px rgba(0,0,0,.25)"></div>`,
    iconSize: [18, 18],
    iconAnchor: [9, 18],
  })
}

export default function TrackWork() {
  const nav = useNavigate()
  const [sheetUp, setSheetUp] = useState(true)
  const [details, setDetails] = useState(false)
  const order = loadSharedOrder()
  const unitLabel = order?.unit || '1713'
  const etaDays = order?.lines?.length ? etaDaysFromLines(order.lines) : null
  const summary = order?.lines?.length ? etaSummary(order.lines) : null
  const propLabel = order?.property || 'Thornbury at Chase Oaks'
  const [liveNote, setLiveNote] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      const { items, error } = await getWorkItems()
      if (cancelled) return
      if (error || !items.length) {
        setLiveNote(null)
        return
      }
      const match = items.find((i) => String(i.unit || '').includes(unitLabel)) || items[0]
      const services = match.services?.length ? match.services.slice(0, 3).join(' · ') : match.title
      setLiveNote(`${match.jobNo || 'Job'} · ${services}`)
    })()
    return () => { cancelled = true }
  }, [unitLabel])

  return (
    <div className="h-full relative overflow-hidden theme-light bg-paper text-ink">
      {/* Map top 45% */}
      <div className="absolute inset-x-0 top-0 h-[45%]">
        <MapContainer center={CENTER} zoom={16} className="h-full w-full" zoomControl={false} attributionControl={false}>
          <TileLayer url="https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png" />
          <Marker position={CENTER} icon={unitPin()} />
          <CircleMarker
            center={[CENTER[0] + 0.0012, CENTER[1] - 0.0008]}
            radius={8}
            pathOptions={{ color: '#fff', fillColor: '#E3B85C', fillOpacity: 1, weight: 2 }}
          />
        </MapContainer>
        <button
          type="button"
          onClick={() => nav('/live')}
          className="absolute top-[max(12px,env(safe-area-inset-top))] left-3 z-20 press h-11 w-11 rounded-full bg-white shadow-lg grid place-items-center"
        >
          <ArrowLeft className="h-5 w-5" />
        </button>
      </div>

      {/* Bottom sheet */}
      <div
        className={cn(
          'absolute inset-x-0 bottom-0 z-30 bg-white rounded-t-[24px] shadow-[0_-8px_40px_rgba(0,0,0,0.1)] flex flex-col transition-[height] duration-300 ease-[cubic-bezier(0.2,0.7,0.2,1)]',
          sheetUp ? 'h-[58%]' : 'h-[32%]',
        )}
      >
        <button
          type="button"
          className="flex justify-center pt-2.5 pb-1 shrink-0"
          onClick={() => setSheetUp((s) => !s)}
        >
          <div className="h-[5px] w-9 rounded-full bg-black/15" />
        </button>

        <div className="px-[22px] pb-2 shrink-0">
          <h1 className="text-[22px] font-bold tracking-[-0.03em]">{`Unit ${unitLabel} is curing`}</h1>
          <p className="mt-1 text-[14px] text-text-muted">
            On schedule · reopens <span className="font-semibold text-ink">Tue 7:40 AM</span>
          </p>
          {liveNote && (
            <p className="mt-1 text-[11px] mono text-ok">Live · {liveNote}</p>
          )}
        </div>

        <div className="flex-1 overflow-y-auto px-[22px] pb-8 space-y-6">
          <ServiceEtaStack
            days={etaDays || DAYS}
            summary={summary?.text || 'Unit complete on schedule'}
            summaryWarn={summary?.warn}
          />

          {/* Active crew */}
          <div className="rounded-[16px] border border-line p-4">
            <div className="text-[11px] mono uppercase tracking-[0.16em] text-text-muted mb-3">Next up</div>
            <div className="flex items-center gap-3">
              <div className="h-11 w-11 rounded-full bg-ink text-gold grid place-items-center font-bold text-[14px]">
                JM
              </div>
              <div className="flex-1 min-w-0">
                <div className="text-[15px] font-semibold">Jose M</div>
                <div className="text-[13px] text-text-muted">Paint · starts after cure</div>
              </div>
              <button type="button" className="press h-10 w-10 rounded-full border border-line grid place-items-center">
                <Phone className="h-4 w-4" />
              </button>
              <button type="button" className="press h-10 w-10 rounded-full border border-line grid place-items-center">
                <MessageCircle className="h-4 w-4" />
              </button>
            </div>
          </div>

          <button
            type="button"
            onClick={() => setDetails((d) => !d)}
            className="press w-full flex items-center justify-between rounded-full border border-line px-4 py-3 text-[14px] font-semibold"
          >
            Order details
            {details ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </button>
          <button
            type="button"
            onClick={() => nav('/complete')}
            className="press w-full rounded-full bg-ink text-white font-bold text-[15px] py-3.5"
          >
            Mark complete · review photos
          </button>

          {details && (
            <div className="rounded-[16px] border border-line divide-y divide-line text-[14px]">
              {[
                ['Wall Prep & Paint', 23000],
                ['Vacant Unit Clean', 15000],
                ['Carpet Clean', 9500],
                ['Garden Tub Resurface', 37500],
              ].map(([n, p]) => (
                <div key={String(n)} className="flex justify-between px-4 py-3">
                  <span>{n}</span>
                  <span className="mono font-medium">{formatMoney(Number(p))}</span>
                </div>
              ))}
              <div className="flex justify-between px-4 py-3 font-semibold">
                <span>Total authorized</span>
                <span className="mono">{formatMoney(85000)}</span>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
