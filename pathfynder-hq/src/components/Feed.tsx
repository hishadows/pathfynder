import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { fetchFeed, type FeedRow, type FeedType } from '../lib/api'
import { torontoToday } from '../lib/time'
import type { Range } from './DateFilter'
import RideCard from './RideCard'

type Mode = 'live' | 'today' | 'past'
const PAGE = 30

export default function Feed({ range }: { range: Range }) {
  const [mode, setMode] = useState<Mode>('live')
  const [type, setType] = useState<FeedType>('all')
  const [search, setSearch] = useState('')
  const [debounced, setDebounced] = useState('')
  const [rows, setRows] = useState<FeedRow[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(0)
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  // The effective day-range depends on the mode.
  const days = useMemo(() => {
    const t = torontoToday()
    if (mode === 'today') return { start: t, end: t }
    if (mode === 'live') return { start: t, end: t }        // live = today's stream, newest first
    return { start: range.start, end: range.end }           // past = whatever the global filter says
  }, [mode, range.start, range.end])

  // Debounce search input.
  useEffect(() => {
    const id = setTimeout(() => setDebounced(search.trim()), 350)
    return () => clearTimeout(id)
  }, [search])

  // Reset to first page whenever the query shape changes.
  useEffect(() => { setPage(0) }, [mode, type, debounced, range.start, range.end])

  const load = useCallback(async () => {
    setLoading(true); setErr(null)
    try {
      const { rows, total } = await fetchFeed({
        startDay: days.start, endDay: days.end, type, search: debounced,
        limit: PAGE, offset: page * PAGE,
      })
      setRows(rows); setTotal(total)
    } catch (e: any) {
      setErr(e?.message ?? 'Failed to load feed')
      setRows([]); setTotal(0)
    } finally {
      setLoading(false)
    }
  }, [days.start, days.end, type, debounced, page])

  useEffect(() => { load() }, [load])

  // Live auto-refresh every 15s on page 0.
  const liveTimer = useRef<number | null>(null)
  useEffect(() => {
    if (liveTimer.current) clearInterval(liveTimer.current)
    if (mode === 'live' && page === 0) {
      liveTimer.current = window.setInterval(load, 15000)
    }
    return () => { if (liveTimer.current) clearInterval(liveTimer.current) }
  }, [mode, page, load])

  const pages = Math.max(1, Math.ceil(total / PAGE))

  const Tab = ({ m, label }: { m: Mode; label: string }) => (
    <button onClick={() => setMode(m)}
      className={`px-3.5 py-2 text-xs font-semibold rounded-lg transition-colors ${
        mode === m ? 'bg-accent text-white' : 'bg-surface2 text-txt-dim hover:text-txt'}`}>
      {label}
    </button>
  )

  const TypeChip = ({ t, label }: { t: FeedType; label: string }) => (
    <button onClick={() => setType(t)}
      className={`chip ${type === t ? 'bg-accent/15 border-accent/40 text-accent' : 'bg-surface2 border-border text-txt-dim'}`}>
      {label}
    </button>
  )

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center gap-2 flex-wrap">
        <Tab m="live" label="🔴 Live" />
        <Tab m="today" label="Today" />
        <Tab m="past" label="Past" />
        {mode === 'live' && <span className="text-[11px] text-txt-muted">auto-refresh · 15s</span>}
        {mode === 'past' && <span className="text-[11px] text-txt-muted">{range.label}</span>}
      </div>

      <div className="flex items-center gap-2 flex-wrap">
        <div className="relative flex-1 min-w-[180px]">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#4e5a6e" strokeWidth="2"
            className="absolute left-3 top-1/2 -translate-y-1/2">
            <circle cx="11" cy="11" r="7" /><path d="M21 21l-4-4" strokeLinecap="round" />
          </svg>
          <input value={search} onChange={(e) => setSearch(e.target.value)}
            placeholder="Search name, phone, city, group, message…"
            className="w-full bg-surface2 border border-border rounded-lg pl-9 pr-3 py-2 text-xs text-txt outline-none focus:border-accent placeholder:text-txt-muted" />
        </div>
        <TypeChip t="all" label="All" />
        <TypeChip t="passenger" label="Passengers" />
        <TypeChip t="driver" label="Drivers" />
      </div>

      <div className="flex items-center justify-between text-[11px] text-txt-muted">
        <span>{loading ? 'Loading…' : `${total.toLocaleString()} result${total === 1 ? '' : 's'}`}</span>
        {pages > 1 && <span>Page {page + 1} / {pages}</span>}
      </div>

      {err && <div className="card border-red/30 bg-red/5 text-red text-xs p-3">{err}</div>}

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
        {rows.map((r) => <RideCard key={r.id} r={r} />)}
      </div>

      {!loading && !rows.length && !err && (
        <div className="card text-txt-muted text-xs py-10 text-center">No messages in this window.</div>
      )}

      {pages > 1 && (
        <div className="flex items-center justify-center gap-2 pt-1">
          <button disabled={page === 0} onClick={() => setPage((p) => Math.max(0, p - 1))}
            className="chip bg-surface2 border-border text-txt-dim disabled:opacity-40">Prev</button>
          <span className="text-xs text-txt-muted font-display">{page + 1}</span>
          <button disabled={page + 1 >= pages} onClick={() => setPage((p) => p + 1)}
            className="chip bg-surface2 border-border text-txt-dim disabled:opacity-40">Next</button>
        </div>
      )}
    </div>
  )
}
