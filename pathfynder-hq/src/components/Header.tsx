import { useEffect, useState } from 'react'
import { nowInToronto } from '../lib/time'

export default function Header({ onRefresh, refreshing }: { onRefresh: () => void; refreshing: boolean }) {
  const [clock, setClock] = useState(nowInToronto())
  useEffect(() => {
    const t = setInterval(() => setClock(nowInToronto()), 1000)
    return () => clearInterval(t)
  }, [])

  return (
    <header className="bg-surface border-b border-border h-14 px-4 sm:px-6 flex items-center gap-3 sticky top-0 z-50">
      <div className="w-[34px] h-[34px] bg-accent rounded-lg flex items-center justify-center shrink-0">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.2"
          strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="2.5" fill="#fff" stroke="none" />
        </svg>
      </div>
      <div className="font-display text-[17px] font-bold">Path<span className="text-accent">fynder</span></div>
      <div className="hidden sm:block w-px h-5 bg-border" />
      <div className="hidden sm:block seclabel">Founder HQ</div>
      <div className="ml-auto flex items-center gap-3">
        <div className="flex items-center gap-1.5">
          <span className="w-1.5 h-1.5 rounded-full bg-green" style={{ boxShadow: '0 0 6px #22c55e' }} />
          <span className="hidden xs:inline font-display text-xs font-semibold text-txt-dim">{clock}</span>
        </div>
        <button onClick={onRefresh} disabled={refreshing}
          className="flex items-center gap-1.5 text-[11px] text-txt-muted bg-surface2 border border-border rounded-lg px-2.5 py-1.5 hover:border-accent hover:text-accent disabled:opacity-50">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2"
            strokeLinecap="round" strokeLinejoin="round" className={refreshing ? 'animate-spin' : ''}>
            <path d="M21 12a9 9 0 1 1-2.64-6.36M21 3v6h-6" />
          </svg>
          <span className="hidden xs:inline">{refreshing ? 'Syncing' : 'Refresh'}</span>
        </button>
      </div>
    </header>
  )
}
