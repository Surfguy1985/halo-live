import type { CartLine } from './catalog'
import type { EtaDay, EtaRow } from '@/components/ServiceEtaStack'

/** Build multi-day ETA stack from cart/shared order lines */
export function etaDaysFromLines(lines: CartLine[], start = new Date()): EtaDay[] {
  if (!lines.length) return demoDays()

  // Sort: long cures early, then by duration
  const sorted = [...lines].sort((a, b) => b.cureHours - a.cureHours || b.durationHours - a.durationHours)
  const days: EtaDay[] = []
  let cursor = new Date(start)
  let dayRows: EtaRow[] = []
  let dayStart = new Date(cursor)
  let hoursOnDay = 0

  function flushDay(labelDate: Date) {
    if (!dayRows.length) return
    const label = formatDayLabel(labelDate)
    days.push({ label, rows: dayRows })
    dayRows = []
    hoursOnDay = 0
  }

  sorted.forEach((line, idx) => {
    const work = line.durationHours * line.qty
    const cure = line.cureHours * line.qty
    const isFirst = idx === 0

    if (hoursOnDay + work > 10 && dayRows.length) {
      flushDay(dayStart)
      cursor = addHours(cursor, 14) // next morning-ish
      dayStart = new Date(cursor)
    }

    if (isFirst && work > 0) {
      dayRows.push({
        kind: 'progress',
        id: line.familyId + '-p',
        title: line.name,
        crew: 'Assigned crew',
        finishBy: formatTime(addHours(cursor, work)),
      })
    } else if (idx === 0) {
      dayRows.push({
        kind: 'done',
        id: line.familyId + '-d',
        title: line.name,
        detail: 'Logged',
      })
    } else {
      dayRows.push({
        kind: 'waiting',
        id: line.familyId + '-w',
        title: line.name,
        after: sorted[idx - 1]?.name || 'prior service',
      })
    }

    hoursOnDay += work
    cursor = addHours(cursor, work)

    if (cure >= 12) {
      dayRows.push({
        kind: 'cure',
        id: line.familyId + '-cure',
        scale: 'long',
        title: 'Unit closed — curing',
        remaining: `${Math.round(cure)}h`,
        reopens: formatTime(addHours(cursor, cure)),
        reason: `${line.name} drying`,
      })
      flushDay(dayStart)
      cursor = addHours(cursor, cure)
      dayStart = new Date(cursor)
    } else if (cure > 0) {
      dayRows.push({
        kind: 'cure',
        id: line.familyId + '-cure',
        scale: 'short',
        title: 'Setting',
        remaining: `${cure}h`,
        reopens: formatTime(addHours(cursor, cure)),
        reason: `${line.name} sets`,
      })
      cursor = addHours(cursor, cure)
      hoursOnDay += cure
    }
  })

  flushDay(dayStart)
  if (!days.length) return demoDays()
  return days
}

export function etaSummary(lines: CartLine[]): { text: string; warn: boolean } {
  let work = 0
  let wait = 0
  for (const l of lines) {
    work += l.durationHours * l.qty
    wait += l.cureHours * l.qty
  }
  const days = Math.max(1, Math.ceil((work + wait) / 10))
  const finish = addHours(new Date(), work + wait)
  const warn = wait >= 12
  return {
    text: `Unit complete ${formatDayLabel(finish)} · ${days} day${days > 1 ? 's' : ''} · ${Math.round(work)}h worked, ${Math.round(wait)}h curing`,
    warn,
  }
}

function demoDays(): EtaDay[] {
  return [
    {
      label: formatDayLabel(new Date()),
      rows: [
        { kind: 'done', id: 'd1', title: 'Trash Out', detail: 'Complete' },
        {
          kind: 'cure',
          id: 'c1',
          scale: 'long',
          title: 'Unit closed — curing',
          remaining: '18h',
          reopens: 'Tomorrow AM',
          reason: 'Resurface drying',
        },
      ],
    },
  ]
}

function addHours(d: Date, h: number) {
  return new Date(d.getTime() + h * 3600_000)
}

function formatTime(d: Date) {
  return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
}

function formatDayLabel(d: Date) {
  return d.toLocaleDateString([], { weekday: 'short', month: 'short', day: 'numeric' })
}
