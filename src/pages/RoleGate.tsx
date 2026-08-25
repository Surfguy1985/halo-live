import { useNavigate } from 'react-router-dom'
import { Building2, Radio, HardHat, ArrowRight } from 'lucide-react'
import { HaloLogo } from '@/components/HaloLogo'
import { setRole, type Role } from '@/lib/api'
import { roleHome } from '@/components/AppTabs'
import { cn } from '@/lib/cn'

const roles: { id: Role; title: string; subtitle: string; detail: string; icon: typeof Building2 }[] = [
  {
    id: 'portfolio',
    title: 'Portfolio',
    subtitle: 'Corporate ops',
    detail: 'Live map · dispatch · PO oversight',
    icon: Building2,
  },
  {
    id: 'pulse',
    title: 'Pulse',
    subtitle: 'Property side',
    detail: 'Approve orders · PO authorize · track cures',
    icon: Radio,
  },
  {
    id: 'vendor',
    title: 'Field / Vendor',
    subtitle: 'Halo ops',
    detail: 'Walk units · build order · dispatch · crew',
    icon: HardHat,
  },
]

export default function RoleGate() {
  const nav = useNavigate()

  function enter(role: Role) {
    setRole(role)
    nav(roleHome(role))
  }

  return (
    <div className="min-h-full bg-ink text-[#F2F5FA] page-enter flex flex-col max-w-lg mx-auto">
      <header className="px-[22px] pt-[max(2.5rem,env(safe-area-inset-top))] pb-4">
        <HaloLogo className="h-8 w-8" />
        <h1 className="mt-8 text-[32px] font-bold tracking-[-0.035em]">Join the live order</h1>
        <p className="mt-2 text-[15px] text-slate max-w-md leading-relaxed">
          One order. Four views. Field builds it, property authorizes with a PO, crews accept,
          dispatch keeps the chain moving — including cure windows.
        </p>
      </header>

      <div className="flex-1 px-4 pb-10 space-y-3">
        {roles.map((r) => {
          const Icon = r.icon
          return (
            <button
              key={r.id}
              type="button"
              onClick={() => enter(r.id)}
              className={cn(
                'press group w-full text-left rounded-[16px] border border-ink-line bg-ink-raised p-5',
                'hover:border-gold/40 transition-colors',
              )}
            >
              <div className="flex items-start gap-4">
                <div className="h-12 w-12 rounded-[12px] bg-gold/10 border border-gold/25 grid place-items-center shrink-0">
                  <Icon className="h-5 w-5 text-gold" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between gap-2">
                    <div>
                      <div className="text-[18px] font-semibold">{r.title}</div>
                      <div className="text-gold text-[11px] font-semibold uppercase tracking-wider mt-0.5">
                        {r.subtitle}
                      </div>
                    </div>
                    <ArrowRight className="h-5 w-5 text-slate-dim group-hover:text-gold transition-colors" />
                  </div>
                  <p className="mt-2 text-[14px] text-slate leading-relaxed">{r.detail}</p>
                </div>
              </div>
            </button>
          )
        })}
      </div>
    </div>
  )
}
