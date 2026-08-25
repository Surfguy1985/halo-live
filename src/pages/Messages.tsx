import { useEffect, useRef, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ArrowLeft, Loader2, Send } from 'lucide-react'
import {
  getMessages, postMessage, getRoleFromStorage, getPlate, type Message, type Role,
} from '@/lib/api'
import { cn } from '@/lib/cn'

export default function Messages() {
  const { buildingId } = useParams()
  const role = (getRoleFromStorage() || 'pulse') as Role
  const dark = role === 'vendor'
  const [msgs, setMsgs] = useState<Message[]>([])
  const [text, setText] = useState('')
  const [buildingLabel, setBuildingLabel] = useState(buildingId || 'Site')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [sending, setSending] = useState(false)
  const bottomRef = useRef<HTMLDivElement>(null)
  const id = buildingId || 'site'

  useEffect(() => {
    setLoading(true)
    getMessages(id).then((r) => {
      setMsgs(r.messages)
      setError(r.error || null)
      setLoading(false)
    })
    getPlate(role).then((p) => {
      const b = p.buildings.find((x) => x.id === id)
      if (b) setBuildingLabel(b.name)
      else if (p.propertyName) setBuildingLabel(p.propertyName)
    })
  }, [id, role])

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [msgs])

  async function send() {
    const body = text.trim()
    if (!body) return
    setSending(true)
    const res = await postMessage(
      id,
      body,
      role === 'vendor' ? 'Halo' : role === 'portfolio' ? 'Portfolio' : 'Property',
      role,
    )
    setSending(false)
    if (res.error || !res.message) {
      setError(res.error || 'Send failed')
      return
    }
    setMsgs((m) => [...m, res.message!])
    setText('')
    setError(null)
  }

  return (
    <div
      className={cn(
        'mx-auto flex min-h-[100dvh] max-w-lg flex-col page-enter',
        dark ? 'bg-ink text-[#F2F5FA]' : 'bg-paper text-ink',
      )}
    >
      <header
        className={cn(
          'flex items-center gap-3 px-4 py-3 sticky top-0 z-20 border-b',
          dark ? 'bg-ink/95 border-ink-line backdrop-blur' : 'bg-white/95 border-line backdrop-blur',
        )}
      >
        <Link
          to="/live"
          className={cn(
            'grid h-10 w-10 place-items-center rounded-full',
            dark ? 'hover:bg-ink-hover' : 'bg-black/5',
          )}
        >
          <ArrowLeft className="h-5 w-5" />
        </Link>
        <div className="min-w-0 flex-1">
          <div className="text-[16px] font-semibold truncate">{buildingLabel}</div>
          <div className={cn('text-[11px] mono', dark ? 'text-slate-dim' : 'text-text-muted')}>
            Live activity · same order
          </div>
        </div>
      </header>

      <div className={cn('flex-1 space-y-3 overflow-y-auto px-[22px] py-4 pb-28', dark ? 'bg-ink' : 'bg-paper')}>
        {loading && (
          <div className="flex justify-center py-12 text-slate-dim">
            <Loader2 className="h-6 w-6 animate-spin" />
          </div>
        )}
        {!loading && !msgs.length && (
          <div className="text-center py-16 px-6">
            <p className={cn('text-[16px] font-semibold', dark ? 'text-[#F2F5FA]' : 'text-ink')}>
              Nothing on the board yet
            </p>
            <p className={cn('mt-2 text-[14px] leading-relaxed', dark ? 'text-slate' : 'text-text-muted')}>
              When crews log work or photos land, they show up here for everyone on this unit.
            </p>
            {error && <p className="mt-3 text-[12px] text-danger">{error}</p>}
          </div>
        )}
        {msgs.map((m) => {
          const mine =
            (role === 'vendor' && m.role === 'vendor') ||
            (role === 'pulse' && m.role === 'pulse') ||
            (role === 'portfolio' && m.role === 'portfolio')
          return (
            <div key={m.id} className={cn('flex', mine ? 'justify-end' : 'justify-start')}>
              <div
                className={cn(
                  'max-w-[80%] rounded-[16px] px-3.5 py-2.5',
                  mine
                    ? 'bg-gold text-ink rounded-br-sm'
                    : dark
                      ? 'bg-ink-raised border border-ink-line rounded-bl-sm'
                      : 'bg-white border border-line rounded-bl-sm',
                )}
              >
                <div className={cn('text-[11px] font-semibold mb-0.5', mine ? 'text-ink/70' : dark ? 'text-gold' : 'text-gold-deep')}>
                  {m.author}
                </div>
                <div className="text-[14px] leading-snug">{m.body}</div>
                <div className={cn('text-[10px] mono mt-1', mine ? 'text-ink/50' : 'text-slate-dim')}>
                  {new Date(m.createdAt).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}
                </div>
              </div>
            </div>
          )
        })}
        <div ref={bottomRef} />
      </div>

      <div
        className={cn(
          'fixed bottom-0 inset-x-0 max-w-lg mx-auto border-t p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]',
          dark ? 'bg-ink border-ink-line' : 'bg-white border-line',
        )}
      >
        <div className="flex gap-2">
          <input
            value={text}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && send()}
            placeholder="Message the unit…"
            className={cn(
              'flex-1 rounded-full px-4 py-2.5 text-[15px] outline-none',
              dark
                ? 'bg-ink-raised border border-ink-line text-[#F2F5FA] placeholder:text-slate-dim focus:border-gold'
                : 'bg-paper border border-line text-ink placeholder:text-text-muted focus:border-gold-deep',
            )}
          />
          <button
            type="button"
            disabled={sending || !text.trim()}
            onClick={send}
            className="press h-11 w-11 rounded-full bg-gold text-ink grid place-items-center disabled:opacity-40"
          >
            {sending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
          </button>
        </div>
      </div>
    </div>
  )
}
