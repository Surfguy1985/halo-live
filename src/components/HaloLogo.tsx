import { cn } from '@/lib/cn'

export function HaloLogo({
  className,
  size = 28,
  light = false,
}: {
  className?: string
  size?: number
  light?: boolean
}) {
  return (
    <div className={cn('inline-flex items-center gap-2', className)}>
      <svg width={size} height={size} viewBox="0 0 32 32" fill="none" aria-hidden>
        <circle cx="16" cy="16" r="14" stroke="#B4FF44" strokeWidth="2" />
        <circle cx="16" cy="16" r="6" fill="#B4FF44" />
        <path
          d="M16 2v4M16 26v4M2 16h4M26 16h4"
          stroke="#B4FF44"
          strokeWidth="1.5"
          strokeLinecap="round"
          opacity="0.5"
        />
      </svg>
      <span
        className={cn(
          'font-semibold tracking-tight',
          light ? 'text-ink' : 'text-white',
        )}
      >
        HALO<span className="text-lime">.</span>
      </span>
    </div>
  )
}
