import type { WindowStats } from '../lib/api'

function Kpi({ label, value, sub, color }: { label: string; value: string; sub?: string; color: string }) {
  return (
    <div className="card p-4 relative overflow-hidden">
      <div className="absolute inset-0 pointer-events-none" style={{ background: `linear-gradient(135deg, ${color}14, transparent 60%)` }} />
      <div className="seclabel mb-2 relative">{label}</div>
      <div className="font-display text-2xl sm:text-3xl font-bold leading-none relative">{value}</div>
      {sub && <div className="text-[11px] text-txt-muted mt-1.5 relative">{sub}</div>}
    </div>
  )
}

export default function KpiStrip({ s, loading }: { s: WindowStats | null; loading: boolean }) {
  const n = (v: number) => v.toLocaleString('en-CA')
  const geoTotal = s ? s.geo_ok + s.geo_failed : 0
  const geoPct = s && geoTotal ? Math.round((s.geo_ok / geoTotal) * 100) : 0
  const urgentPct = s && s.total ? Math.round((s.urgent / s.total) * 100) : 0
  const paxPerDriver = s && s.drivers ? (s.passengers / s.drivers).toFixed(1) : '—'

  if (loading || !s) {
    return (
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="card p-4 h-[92px] animate-pulse opacity-40" />
        ))}
      </div>
    )
  }

  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
      <Kpi label="Messages" value={n(s.total)} sub={`${n(s.unique_senders)} unique senders`} color="#4f8ef7" />
      <Kpi label="Passengers" value={n(s.passengers)} sub={`${s.total ? Math.round((s.passengers / s.total) * 100) : 0}% of volume`} color="#a855f7" />
      <Kpi label="Drivers" value={n(s.drivers)} sub={`${paxPerDriver} pax / driver`} color="#22c55e" />
      <Kpi label="Active groups" value={n(s.active_groups)} sub="source WhatsApp groups" color="#06b6d4" />
      <Kpi label="Urgent" value={`${urgentPct}%`} sub={`${n(s.urgent)} asap / urgent`} color="#f59e0b" />
      <Kpi label="Geocode OK" value={`${geoPct}%`} sub={`${n(s.geo_failed)} failed`} color={geoPct >= 80 ? '#22c55e' : '#ef4444'} />
    </div>
  )
}
