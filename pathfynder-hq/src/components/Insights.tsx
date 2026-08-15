import { useEffect, useState } from 'react'
import {
  ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid, Legend,
} from 'recharts'
import { fetchDailySeries, fetchCorridors, fetchGroups, type DayPoint } from '../lib/api'
import type { Range } from './DateFilter'

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <div className="flex items-center gap-2 mb-2.5">
        <span className="seclabel whitespace-nowrap">{label}</span>
        <span className="flex-1 h-px bg-border" />
      </div>
      {children}
    </div>
  )
}

const tooltipStyle = {
  background: '#1e2740', border: '1px solid #2a3a58', borderRadius: 8,
  fontSize: 12, color: '#e8edf5',
}

export default function Insights({ range }: { range: Range }) {
  const [daily, setDaily] = useState<DayPoint[]>([])
  const [corridors, setCorridors] = useState<any[]>([])
  const [groups, setGroups] = useState<any[]>([])

  useEffect(() => {
    let alive = true
    fetchDailySeries(range.start, range.end).then((d) => alive && setDaily(d)).catch(() => {})
    fetchCorridors(8).then((d) => alive && setCorridors(d)).catch(() => {})
    fetchGroups(8).then((d) => alive && setGroups(d)).catch(() => {})
    return () => { alive = false }
  }, [range.start, range.end])

  const maxCorridor = Math.max(1, ...corridors.map((c) => c.n))
  const maxGroup = Math.max(1, ...groups.map((g) => g.n))
  const shortCity = (s: string) => (s || '').split(',')[0]

  return (
    <div className="flex flex-col gap-5">
      <Section label="Message volume — Toronto days">
        <div className="card p-4">
          <div className="h-[220px]">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={daily} margin={{ top: 6, right: 10, left: -18, bottom: 0 }}>
                <CartesianGrid stroke="#222d44" vertical={false} />
                <XAxis dataKey="day" tick={{ fill: '#4e5a6e', fontSize: 10 }} tickFormatter={(d) => d.slice(5)} minTickGap={24} />
                <YAxis tick={{ fill: '#4e5a6e', fontSize: 10 }} />
                <Tooltip contentStyle={tooltipStyle} />
                <Legend wrapperStyle={{ fontSize: 11 }} />
                <Line type="monotone" dataKey="passengers" stroke="#a855f7" strokeWidth={2} dot={false} />
                <Line type="monotone" dataKey="drivers" stroke="#22c55e" strokeWidth={2} dot={false} />
                <Line type="monotone" dataKey="total" stroke="#4f8ef7" strokeWidth={2} dot={false} />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>
      </Section>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5">
        <Section label="Top corridors (all-time)">
          <div className="card p-4 flex flex-col gap-2.5">
            {corridors.map((c, i) => (
              <div key={i} className="flex items-center gap-3 text-xs">
                <span className="w-[130px] sm:w-[180px] shrink-0 text-txt truncate">
                  {shortCity(c.pickup)} <span className="text-txt-muted">→</span> {shortCity(c.dropoff)}
                </span>
                <div className="flex-1 h-2 bg-surface2 rounded-full overflow-hidden">
                  <div className="h-full bg-accent rounded-full" style={{ width: `${(c.n / maxCorridor) * 100}%` }} />
                </div>
                <span className="font-display font-semibold text-txt w-10 text-right">{c.n.toLocaleString()}</span>
              </div>
            ))}
            {!corridors.length && <div className="text-txt-muted text-xs py-4 text-center">No data</div>}
          </div>
        </Section>

        <Section label="Busiest groups (all-time)">
          <div className="card p-4 flex flex-col gap-2.5">
            {groups.map((g, i) => (
              <div key={i} className="flex items-center gap-3 text-xs">
                <span className="w-[130px] sm:w-[180px] shrink-0 text-txt truncate">{g.group_name}</span>
                <div className="flex-1 h-2 bg-surface2 rounded-full overflow-hidden">
                  <div className="h-full bg-cyan rounded-full" style={{ width: `${(g.n / maxGroup) * 100}%` }} />
                </div>
                <span className="font-display font-semibold text-txt w-10 text-right">{g.n.toLocaleString()}</span>
              </div>
            ))}
            {!groups.length && <div className="text-txt-muted text-xs py-4 text-center">No data</div>}
          </div>
        </Section>
      </div>
    </div>
  )
}
