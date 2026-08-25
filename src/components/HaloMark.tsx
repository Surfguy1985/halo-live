/** Vector HALO mark — wings + ring (brand) */
export function HaloRing({ className = 'h-24 w-24', glow }: { className?: string; glow?: boolean }) {
  return (
    <svg viewBox="0 0 120 120" className={className} fill="none" aria-hidden>
      {glow && (
        <circle cx="60" cy="60" r="42" stroke="#B4FF44" strokeWidth="1" opacity="0.25">
          <animate attributeName="r" values="38;46;38" dur="3s" repeatCount="indefinite" />
          <animate attributeName="opacity" values="0.15;0.35;0.15" dur="3s" repeatCount="indefinite" />
        </circle>
      )}
      <circle cx="60" cy="60" r="34" stroke="#E3B85C" strokeWidth="6" />
      <circle cx="60" cy="60" r="28" stroke="rgba(255,255,255,0.35)" strokeWidth="2" />
      <circle cx="60" cy="60" r="18" stroke="#B4FF44" strokeWidth="2" opacity="0.6" />
    </svg>
  )
}

export function HaloWings({ className = 'h-10 w-10' }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 40" className={className} fill="currentColor" aria-hidden>
      <path d="M32 20C28 8 18 2 4 4c6 8 10 16 10 24 8-4 14-6 18-8z" opacity="0.95" />
      <path d="M32 20C36 8 46 2 60 4c-6 8-10 16-10 24-8-4-14-6-18-8z" opacity="0.95" />
    </svg>
  )
}

export function HaloWordmark({ className = 'text-white', size = 'lg' }: { className?: string; size?: 'sm' | 'lg' }) {
  const text = size === 'lg' ? 'text-[42px]' : 'text-[22px]'
  return (
    <div className={`flex items-center gap-3 ${className}`}>
      <HaloWings className={size === 'lg' ? 'h-12 w-14' : 'h-7 w-8'} />
      <span className={`${text} font-bold tracking-[0.12em] leading-none`}>HALO</span>
      <svg viewBox="0 0 28 28" className={size === 'lg' ? 'h-8 w-8' : 'h-5 w-5'} fill="none">
        <circle cx="14" cy="14" r="10" stroke="currentColor" strokeWidth="2.5" />
        <circle cx="14" cy="14" r="5" stroke="currentColor" strokeWidth="1.5" opacity="0.5" />
      </svg>
    </div>
  )
}

/** GPS orbit illustration for live/onboarding */
export function OrbitPins({ className = 'h-40 w-40' }: { className?: string }) {
  return (
    <svg viewBox="0 0 200 200" className={className} aria-hidden>
      <circle cx="100" cy="100" r="28" fill="none" stroke="#B4FF44" strokeWidth="4" opacity="0.9" />
      <circle cx="100" cy="100" r="48" fill="none" stroke="#B4FF44" strokeWidth="1" opacity="0.35" strokeDasharray="4 6" />
      <circle cx="100" cy="100" r="68" fill="none" stroke="#B4FF44" strokeWidth="1" opacity="0.2" />
      {/* pins */}
      <g fill="#B4FF44">
        <path d="M70 55c0-8 6-14 14-14s14 6 14 14c0 10-14 22-14 22S70 65 70 55z" />
        <circle cx="84" cy="54" r="4" fill="#080D1A" />
        <path d="M130 120c0-6 5-11 11-11s11 5 11 11c0 8-11 17-11 17s-11-9-11-17z" opacity="0.85" />
        <path d="M45 130c0-5 4-9 9-9s9 4 9 9c0 7-9 14-9 14s-9-7-9-14z" opacity="0.7" />
        <path d="M145 55c0-5 4-9 9-9s9 4 9 9c0 7-9 14-9 14s-9-7-9-14z" opacity="0.55" />
      </g>
    </svg>
  )
}

/** Polaroid stack for photo step */
export function PhotoStack({ className = 'h-36 w-36' }: { className?: string }) {
  return (
    <svg viewBox="0 0 160 160" className={className} aria-hidden>
      <rect x="28" y="36" width="90" height="100" rx="4" fill="#fff" stroke="#E5E5E0" transform="rotate(-6 73 86)" />
      <rect x="38" y="28" width="90" height="100" rx="4" fill="#fff" stroke="#E5E5E0" transform="rotate(4 83 78)" />
      <rect x="42" y="22" width="90" height="100" rx="4" fill="#fff" stroke="#ddd" />
      <rect x="50" y="30" width="74" height="58" fill="#F0F0EA" />
      {/* house sketch */}
      <path d="M62 68 L87 48 L112 68 V82 H62 Z" fill="none" stroke="#999" strokeWidth="1.5" />
      <circle cx="120" cy="108" r="12" fill="#B4FF44" />
      <path d="M114 108 l4 4 8-9" fill="none" stroke="#080D1A" strokeWidth="2.5" strokeLinecap="round" />
    </svg>
  )
}
