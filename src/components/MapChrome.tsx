import { Link } from 'react-router-dom'
import { ArrowLeft, Camera, MessageSquare, HelpCircle } from 'lucide-react'
import { HaloLogo } from './HaloLogo'

export function MapTopBar({ role, buildingId }: { role: string; buildingId?: string | null }) {
  return (
    <div className="pointer-events-none absolute inset-x-0 top-0 z-[1000] p-3 safe-top">
      <div className="pointer-events-auto flex items-center justify-between gap-2">
        <Link
          to="/enter"
          className="grid h-10 w-10 place-items-center rounded-full bg-white text-ink shadow-lg"
          aria-label="Back"
        >
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <div className="flex items-center gap-2 rounded-full bg-white px-3 py-2 shadow-lg">
          <HaloLogo size={16} light className="gap-1" />
          <span className="text-[10px] font-bold uppercase tracking-wider text-slate-dim border-l border-black/10 pl-2">
            {role}
          </span>
        </div>
        <div className="flex gap-2">
          <Link
            to={buildingId ? `/messages/${buildingId}` : '/messages'}
            className="grid h-10 w-10 place-items-center rounded-full bg-white text-ink shadow-lg"
            aria-label="Messages"
          >
            <MessageSquare className="h-5 w-5" />
          </Link>
          <Link
            to="/field"
            className="grid h-10 w-10 place-items-center rounded-full bg-lime text-ink shadow-lg"
            aria-label="Field photos"
          >
            <Camera className="h-5 w-5" />
          </Link>
        </div>
      </div>
    </div>
  )
}

export function MapHelpButton() {
  return (
    <button
      type="button"
      className="pointer-events-auto absolute top-3 right-14 z-[1000] h-10 px-3 rounded-full bg-white text-ink text-sm font-medium shadow-lg hidden sm:flex items-center gap-1"
    >
      <HelpCircle className="h-4 w-4" /> Help
    </button>
  )
}
