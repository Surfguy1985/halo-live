import { useState } from 'react'
import { Camera, X } from 'lucide-react'
import type { FieldPhoto } from '@/lib/api'
import { cn } from '@/lib/cn'

export function FieldPhotoGrid({
  photos,
  emptyLabel = 'No field photos on the plate yet',
  className,
}: {
  photos: FieldPhoto[]
  emptyLabel?: string
  className?: string
}) {
  const [lightbox, setLightbox] = useState<FieldPhoto | null>(null)

  if (!photos.length) {
    return (
      <div
        className={cn(
          'rounded-2xl border border-dashed border-black/12 bg-paper aspect-[16/9] grid place-items-center',
          className,
        )}
      >
        <div className="text-center px-4">
          <Camera className="h-8 w-8 text-slate-dim mx-auto mb-2" strokeWidth={1.25} />
          <p className="text-xs text-slate-dim">{emptyLabel}</p>
        </div>
      </div>
    )
  }

  const before = photos.filter((p) => p.phase === 'before')
  const after = photos.filter((p) => p.phase === 'after')
  const rest = photos.filter((p) => p.phase !== 'before' && p.phase !== 'after')

  return (
    <>
      <div className={cn('space-y-3', className)}>
        {(before.length > 0 || after.length > 0) && (
          <div className="grid grid-cols-2 gap-2">
            <PhaseCol label="Before" items={before} onOpen={setLightbox} />
            <PhaseCol label="After" items={after} onOpen={setLightbox} />
          </div>
        )}
        {rest.length > 0 && (
          <div className="grid grid-cols-3 gap-1.5">
            {rest.slice(0, 9).map((p) => (
              <button
                key={p.id}
                type="button"
                onClick={() => setLightbox(p)}
                className="aspect-square rounded-lg overflow-hidden bg-paper border border-black/8 relative"
              >
                <img
                  src={p.url}
                  alt={p.note || p.phase}
                  className="h-full w-full object-cover"
                  loading="lazy"
                  onError={(e) => {
                    ;(e.target as HTMLImageElement).style.display = 'none'
                  }}
                />
              </button>
            ))}
          </div>
        )}
        {before.length === 0 && after.length === 0 && rest.length === 0 && null}
      </div>

      {lightbox && (
        <div
          className="fixed inset-0 z-[2000] bg-black/80 flex items-center justify-center p-4"
          onClick={() => setLightbox(null)}
        >
          <button
            type="button"
            className="absolute top-4 right-4 grid h-10 w-10 place-items-center rounded-full bg-white/10 text-white"
            onClick={() => setLightbox(null)}
          >
            <X className="h-5 w-5" />
          </button>
          <img
            src={lightbox.url}
            alt={lightbox.note || lightbox.phase}
            className="max-h-[85vh] max-w-full rounded-2xl object-contain"
            onClick={(e) => e.stopPropagation()}
          />
          <div className="absolute bottom-6 left-0 right-0 text-center text-white text-sm">
            <span className="rounded-full bg-black/50 px-3 py-1.5 capitalize">
              {lightbox.phase}
              {lightbox.unitNo ? ` · #${lightbox.unitNo}` : ''}
              {lightbox.note ? ` · ${lightbox.note}` : ''}
            </span>
          </div>
        </div>
      )}
    </>
  )
}

function PhaseCol({
  label,
  items,
  onOpen,
}: {
  label: string
  items: FieldPhoto[]
  onOpen: (p: FieldPhoto) => void
}) {
  return (
    <div>
      <p className="text-[10px] font-bold uppercase tracking-wide text-slate-dim mb-1.5">{label}</p>
      {items[0] ? (
        <button
          type="button"
          onClick={() => onOpen(items[0])}
          className="w-full aspect-[4/3] rounded-xl overflow-hidden border border-black/8 bg-paper relative"
        >
          <img
            src={items[0].url}
            alt={label}
            className="h-full w-full object-cover"
            loading="lazy"
            onError={(e) => {
              ;(e.target as HTMLImageElement).style.opacity = '0.3'
            }}
          />
          {items.length > 1 && (
            <span className="absolute bottom-1.5 right-1.5 rounded-full bg-ink/80 text-white text-[10px] font-bold px-1.5 py-0.5">
              +{items.length - 1}
            </span>
          )}
        </button>
      ) : (
        <div className="aspect-[4/3] rounded-xl border border-dashed border-black/12 bg-paper grid place-items-center">
          <Camera className="h-5 w-5 text-slate-dim" />
        </div>
      )}
    </div>
  )
}
