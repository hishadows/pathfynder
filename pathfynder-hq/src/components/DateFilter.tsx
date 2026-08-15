import { torontoToday, torontoDaysAgo } from '../lib/time'

export interface Range { start: string; end: string; label: string }

const FIRST_DAY = '2026-06-05' // earliest message in the dataset

export const PRESETS: { key: string; label: string; make: () => Range }[] = [
  { key: 'today', label: 'Today', make: () => ({ start: torontoToday(), end: torontoToday(), label: 'Today' }) },
  { key: '7d', label: '7 days', make: () => ({ start: torontoDaysAgo(6), end: torontoToday(), label: 'Last 7 days' }) },
  { key: '30d', label: '30 days', make: () => ({ start: torontoDaysAgo(29), end: torontoToday(), label: 'Last 30 days' }) },
  { key: 'all', label: 'All time', make: () => ({ start: FIRST_DAY, end: torontoToday(), label: 'All time' }) },
]

export default function DateFilter({
  range, activePreset, onPreset, onCustom,
}: {
  range: Range
  activePreset: string
  onPreset: (key: string) => void
  onCustom: (start: string, end: string) => void
}) {
  const today = torontoToday()
  return (
    <div className="card p-3 flex flex-col gap-3">
      <div className="flex items-center gap-2 flex-wrap">
        <span className="seclabel mr-1">Date filter · Toronto</span>
        {PRESETS.map((p) => (
          <button key={p.key} onClick={() => onPreset(p.key)}
            className={`chip ${activePreset === p.key
              ? 'bg-accent/15 border-accent/40 text-accent'
              : 'bg-surface2 border-border text-txt-dim hover:border-border2'}`}>
            {p.label}
          </button>
        ))}
      </div>
      <div className="flex items-center gap-2 flex-wrap">
        <label className="flex items-center gap-1.5 text-xs text-txt-muted">
          From
          <input type="date" value={range.start} max={today} min={FIRST_DAY}
            onChange={(e) => onCustom(e.target.value, range.end)}
            className="bg-surface2 border border-border rounded-lg px-2 py-1.5 text-txt text-xs outline-none focus:border-accent [color-scheme:dark]" />
        </label>
        <label className="flex items-center gap-1.5 text-xs text-txt-muted">
          To
          <input type="date" value={range.end} max={today} min={range.start}
            onChange={(e) => onCustom(range.start, e.target.value)}
            className="bg-surface2 border border-border rounded-lg px-2 py-1.5 text-txt text-xs outline-none focus:border-accent [color-scheme:dark]" />
        </label>
        <span className="text-[11px] text-txt-muted ml-auto">
          Showing <b className="text-txt-dim">{range.label}</b>
        </span>
      </div>
    </div>
  )
}
