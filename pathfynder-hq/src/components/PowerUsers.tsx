import { useEffect, useState } from 'react'
import { fetchPowerUsers, type FeedType, type PowerUser } from '../lib/api'
import { fmtMsgTime } from '../lib/time'
import type { Range } from './DateFilter'

const LIMIT = 15

export default function PowerUsers({ range }: { range: Range }) {
  const [type, setType] = useState<FeedType>('all')
  const [rows, setRows] = useState<PowerUser[]>([])
  const [loading, setLoading] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  useEffect(() => {
    let alive = true
    setLoading(true); setErr(null)
    fetchPowerUsers(range.start, range.end, type, LIMIT)
      .then((d) => { if (alive) setRows(d) })
      .catch((e) => { if (alive) { setErr(e?.message ?? 'Failed to load power users'); setRows([]) } })
      .finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
  }, [range.start, range.end, type])

  const max = Math.max(1, ...rows.map((r) => r.msg_count))
  const shortCity = (s: string | null) => (s || '').split(',')[0]

  const TypeChip = ({ t, label }: { t: FeedType; label: string }) => (
    <button onClick={() => setType(t)}
      className={`chip ${type === t ? 'bg-accent/15 border-accent/40 text-accent' : 'bg-surface2 border-border text-txt-dim'}`}>
      {label}
    </button>
  )

  return (
    <div>
      <div className="flex items-center gap-2 mb-2.5">
        <span className="seclabel whitespace-nowrap">Power users</span>
        <span className="flex-1 h-px bg-border" />
      </div>

      <div className="flex items-center gap-2 flex-wrap mb-3">
        <TypeChip t="all" label="All" />
        <TypeChip t="passenger" label="Passengers" />
        <TypeChip t="driver" label="Drivers" />
      </div>

      {err && <div className="card border-red/30 bg-red/5 text-red text-xs p-3 mb-3">{err}</div>}

      <div className="card p-4 flex flex-col gap-2.5">
        {loading && (
          <div className="flex flex-col gap-2.5">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="h-8 rounded-lg bg-surface2 animate-pulse opacity-40" />
            ))}
          </div>
        )}

        {!loading && rows.map((r, i) => {
          const phone = r.sender_number ? `+${r.sender_number}` : null
          return (
            <div key={r.sender_number ?? i} className="flex items-center gap-3 text-xs">
              <span className="w-5 shrink-0 text-txt-muted font-display text-right">{i + 1}</span>

              <div className="w-[110px] sm:w-[150px] shrink-0 min-w-0">
                <div className="text-txt truncate">{r.sender_name || 'Unknown'}</div>
                {phone && (
                  <a href={`https://wa.me/${r.sender_number}`} target="_blank" rel="noreferrer"
                    className="text-accent text-[10px] truncate block">{phone}</a>
                )}
              </div>

              <div className="flex-1 min-w-[70px] flex flex-col gap-1">
                <div className="h-2 bg-surface2 rounded-full overflow-hidden">
                  <div className="h-full bg-accent rounded-full" style={{ width: `${(r.msg_count / max) * 100}%` }} />
                </div>
                <div className="text-[10px] text-txt-muted truncate">
                  {r.top_pickup || r.top_dropoff
                    ? <>{shortCity(r.top_pickup) || '—'} <span className="text-txt-muted">→</span> {shortCity(r.top_dropoff) || '—'}</>
                    : '—'}
                </div>
              </div>

              <span className="pill bg-purple/10 text-purple border border-purple/20 shrink-0">
                P {r.passenger_count} · D {r.driver_count}
              </span>

              <span className="font-display font-semibold text-txt w-10 text-right shrink-0">{r.msg_count.toLocaleString()}</span>

              <span className="hidden sm:block text-[10px] text-txt-muted font-display w-24 text-right shrink-0">{fmtMsgTime(r.last_seen)}</span>
            </div>
          )
        })}

        {!loading && !rows.length && !err && (
          <div className="text-txt-muted text-xs py-10 text-center">No power users in this window yet.</div>
        )}
      </div>
    </div>
  )
}
