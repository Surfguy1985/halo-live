import { Link, useLocation } from 'react-router-dom'
import { getRoleFromStorage, type Role } from '@/lib/api'
import { cn } from '@/lib/cn'
import { LayoutGrid, Map, ShoppingBag, Camera, Radio, Users, ClipboardList } from 'lucide-react'

type Tab = { to: string; label: string; icon: typeof Map }

const TABS: Record<string, Tab[]> = {
  vendor: [
    { to: '/units', label: 'Units', icon: LayoutGrid },
    { to: '/order', label: 'Menu', icon: ShoppingBag },
    { to: '/live', label: 'Live', icon: Map },
    { to: '/dispatch', label: 'Dispatch', icon: ClipboardList },
  ],
  pulse: [
    { to: '/live', label: 'Live', icon: Map },
    { to: '/approve', label: 'Orders', icon: Radio },
    { to: '/track', label: 'Track', icon: Camera },
    { to: '/messages', label: 'Chat', icon: Users },
  ],
  portfolio: [
    { to: '/live', label: 'Live', icon: Map },
    { to: '/approve', label: 'Orders', icon: Radio },
    { to: '/dispatch', label: 'Dispatch', icon: ClipboardList },
    { to: '/track', label: 'Track', icon: Camera },
  ],
}

export function AppTabs() {
  const role = (getRoleFromStorage() || 'pulse') as Role
  const loc = useLocation()
  const tabs = TABS[role] || TABS.pulse
  const light = role === 'pulse' || role === 'portfolio'
  const hide =
    loc.pathname.startsWith('/crew/ping') ||
    loc.pathname === '/enter' ||
    loc.pathname === '/splash' ||
    loc.pathname === '/onboard' ||
    loc.pathname === '/' ||
    loc.pathname.startsWith('/walk')

  if (hide) return null

  return (
    <nav className="fixed bottom-0 inset-x-0 z-40 pointer-events-none">
      <div
        className={cn(
          'pointer-events-auto mx-auto max-w-lg border-t backdrop-blur pb-[max(0.35rem,env(safe-area-inset-bottom))]',
          light ? 'bg-white/95 border-line' : 'bg-ink/95 border-ink-line',
        )}
      >
        <div className="flex justify-around pt-2">
          {tabs.map((t) => {
            const active = loc.pathname === t.to || loc.pathname.startsWith(t.to + '/')
            const Icon = t.icon
            return (
              <Link
                key={t.to}
                to={t.to}
                className={cn(
                  'flex flex-col items-center gap-0.5 py-1 px-3 min-w-[64px] text-[10px] font-medium',
                  active
                    ? 'text-gold-deep'
                    : light
                      ? 'text-text-muted'
                      : 'text-slate-dim',
                  active && !light && 'text-gold',
                )}
              >
                <Icon className="h-5 w-5" strokeWidth={active ? 2.25 : 1.75} />
                {t.label}
              </Link>
            )
          })}
        </div>
      </div>
    </nav>
  )
}

export function roleHome(role: Role | null): string {
  if (role === 'vendor') return '/units'
  if (role === 'pulse') return '/approve'
  if (role === 'portfolio') return '/live'
  return '/live'
}
