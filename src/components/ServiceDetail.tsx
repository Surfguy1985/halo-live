import { useState } from 'react'
import { X } from 'lucide-react'
import type { ServiceFamily } from '@/lib/catalog'
import { formatMoney, resolveVariant } from '@/lib/catalog'
import { PrimaryCTA } from '@/components/PrimaryCTA'
import { cn } from '@/lib/cn'

const ROOMS = ['Living', 'Kitchen', 'Bath', 'Bed 1', 'Bed 2', 'Bed 3', 'Hall', 'Entry']

export function ServiceDetail({
  family,
  bedrooms,
  onClose,
  onAdd,
}: {
  family: ServiceFamily
  bedrooms: number
  onClose: () => void
  onAdd: (rooms: string[], note: string) => void
}) {
  const v = resolveVariant(family, bedrooms)
  const [rooms, setRooms] = useState<string[]>(family.defaultRooms || ['Living', 'Kitchen', 'Bath'])
  const [note, setNote] = useState('')

  function toggle(r: string) {
    setRooms((prev) => (prev.includes(r) ? prev.filter((x) => x !== r) : [...prev, r]))
  }

  return (
    <div className="fixed inset-0 z-50 flex flex-col justify-end bg-black/50" onClick={onClose}>
      <div
        className="max-w-lg mx-auto w-full rounded-t-[24px] bg-ink-raised border-t border-ink-line max-h-[88vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex justify-center pt-2.5">
          <div className="h-[5px] w-9 rounded-full bg-white/15" />
        </div>
        <div className="flex items-start justify-between px-[22px] pt-3 pb-2">
          <div>
            <div className="text-[11px] mono uppercase tracking-[0.16em] text-slate-dim">{family.category}</div>
            <h2 className="text-[22px] font-bold tracking-[-0.03em] mt-1">{family.name}</h2>
          </div>
          <button type="button" onClick={onClose} className="press h-9 w-9 rounded-full grid place-items-center hover:bg-ink-hover">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="px-[22px] space-y-5 pb-8">
          <p className="text-[14px] text-slate leading-relaxed">{family.description}</p>

          <div className="flex items-center gap-3 flex-wrap">
            <span className="mono text-[22px] font-bold text-gold">{formatMoney(v.priceCents)}</span>
            <span className="mono text-[12px] text-slate-dim">{v.key} rate</span>
            {v.cureHours > 0 && (
              <span className={cn(
                'rounded-full px-2 py-0.5 text-[11px] font-semibold',
                v.cureHours >= 12 ? 'bg-warn/20 text-warn' : 'bg-ink-hover text-slate',
              )}>
                +{v.cureHours}h cure
              </span>
            )}
          </div>

          {v.cureHours >= 12 && (
            <div className="rounded-[12px] border border-warn/30 bg-warn/10 p-3 text-[13px] text-slate leading-snug">
              This closes the unit for {v.cureHours}h. Nobody walks in during the window — it ruins the finish.
            </div>
          )}

          <div>
            <div className="text-[13px] font-semibold mb-2">Rooms</div>
            <div className="flex flex-wrap gap-2">
              {ROOMS.map((r) => (
                <button
                  key={r}
                  type="button"
                  onClick={() => toggle(r)}
                  className={cn(
                    'press rounded-full px-3.5 py-1.5 text-[13px] font-semibold border',
                    rooms.includes(r)
                      ? 'bg-gold text-ink border-gold'
                      : 'border-ink-line text-slate',
                  )}
                >
                  {r}
                </button>
              ))}
            </div>
          </div>

          <div>
            <div className="text-[13px] font-semibold mb-2">Note for crew</div>
            <textarea
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={2}
              placeholder="Match the south wall patch only…"
              className="w-full rounded-[12px] bg-ink border border-ink-line px-3 py-2.5 text-[14px] text-[#F2F5FA] placeholder:text-slate-dim outline-none focus:border-gold"
            />
          </div>

          <PrimaryCTA onClick={() => onAdd(rooms, note)}>
            Add · {formatMoney(v.priceCents)}
          </PrimaryCTA>
        </div>
      </div>
    </div>
  )
}
