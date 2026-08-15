import { useCallback, useEffect, useState } from 'react'
import Gate from './components/Gate'
import Header from './components/Header'
import DateFilter, { PRESETS, type Range } from './components/DateFilter'
import KpiStrip from './components/KpiStrip'
import Feed from './components/Feed'
import Insights from './components/Insights'
import { fetchWindowStats, type WindowStats } from './lib/api'

function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2 mb-3">
      <span className="seclabel whitespace-nowrap">{children}</span>
      <span className="flex-1 h-px bg-border" />
    </div>
  )
}

export default function App() {
  const [authed, setAuthed] = useState(false)
  const [range, setRange] = useState<Range>(PRESETS[2].make()) // default: last 30 days
  const [activePreset, setActivePreset] = useState('30d')
  const [stats, setStats] = useState<WindowStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [nonce, setNonce] = useState(0) // bump to force refresh

  const onPreset = (key: string) => {
    const p = PRESETS.find((x) => x.key === key)
    if (p) { setRange(p.make()); setActivePreset(key) }
  }
  const onCustom = (start: string, end: string) => {
    const s = start <= end ? start : end
    const e = start <= end ? end : start
    setRange({ start: s, end: e, label: s === e ? s : `${s} → ${e}` })
    setActivePreset('custom')
  }

  const loadStats = useCallback(async () => {
    setLoading(true)
    try { setStats(await fetchWindowStats(range.start, range.end)) }
    catch { setStats(null) }
    finally { setLoading(false) }
  }, [range.start, range.end])

  useEffect(() => { if (authed) loadStats() }, [authed, loadStats, nonce])

  if (!authed) return <Gate onPass={() => setAuthed(true)} />

  return (
    <div className="min-h-screen flex flex-col">
      <Header onRefresh={() => setNonce((n) => n + 1)} refreshing={loading} />
      <main className="px-3 sm:px-6 py-4 flex flex-col gap-5 max-w-[1600px] w-full mx-auto pb-16">
        <DateFilter range={range} activePreset={activePreset} onPreset={onPreset} onCustom={onCustom} />

        <div>
          <SectionLabel>Overview · {range.label}</SectionLabel>
          <KpiStrip s={stats} loading={loading} />
        </div>

        <div>
          <SectionLabel>Ride feed</SectionLabel>
          <Feed range={range} key={nonce} />
        </div>

        <Insights range={range} key={`ins-${nonce}`} />

        <footer className="text-center text-[10px] text-txt-muted pt-4">
          Pathfynder Founder HQ · times shown in America/Toronto · data stored UTC
        </footer>
      </main>
    </div>
  )
}
