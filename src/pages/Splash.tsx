import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { HaloRing, HaloWordmark } from '@/components/HaloMark'
import { hasCompletedOnboarding } from '@/lib/onboarding'
import { getRoleFromStorage } from '@/lib/api'
import { roleHome } from '@/components/AppTabs'

export default function Splash() {
  const nav = useNavigate()

  useEffect(() => {
    const t = setTimeout(() => {
      if (hasCompletedOnboarding() && getRoleFromStorage()) {
        nav(roleHome(getRoleFromStorage()), { replace: true })
      } else {
        nav('/onboard', { replace: true })
      }
    }, 2200)
    return () => clearTimeout(t)
  }, [nav])

  return (
    <div className="min-h-[100dvh] bg-ink flex flex-col items-center justify-center page-enter relative overflow-hidden">
      <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,#16243F_0%,#080D1A_65%)]" />
      <div className="relative z-10 flex flex-col items-center gap-8 px-8">
        <HaloRing className="h-28 w-28" glow />
        <HaloWordmark className="text-white" size="lg" />
        <p className="text-[14px] text-slate tracking-wide text-center max-w-xs">
          One live order for make-ready work
        </p>
      </div>
      <button
        type="button"
        onClick={() => nav('/onboard', { replace: true })}
        className="absolute bottom-10 text-[13px] text-slate-dim underline"
      >
        Skip intro
      </button>
    </div>
  )
}
