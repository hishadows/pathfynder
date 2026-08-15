import { useState } from 'react'
import type { FeedRow } from '../lib/api'
import { fmtMsgTime, fmtRideTime } from '../lib/time'

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <div className="text-[9px] uppercase tracking-wide text-txt-muted mb-0.5">{label}</div>
      <div className="text-xs text-txt-dim break-words">{value ?? '—'}</div>
    </div>
  )
}

export default function RideCard({ r }: { r: FeedRow }) {
  const [open, setOpen] = useState(false)
  const isDriver = r.type === 'Driver'
  const urgent = /urgent|asap/i.test(r.important_ride ?? '')
  const geoBad = (r.geo_status ?? '').startsWith('geocode_failed')
  const phone = r.sender_number ? `+${r.sender_number}` : null

  return (
    <div className="card overflow-hidden">
      <button onClick={() => setOpen((o) => !o)} className="w-full text-left p-3.5 flex flex-col gap-2">
        <div className="flex items-center gap-2">
          <span className={`pill ${isDriver ? 'bg-green/10 text-green border border-green/20' : 'bg-purple/10 text-purple border border-purple/20'}`}>
            {isDriver ? 'Driver' : 'Passenger'}
          </span>
          {urgent && <span className="pill bg-amber/10 text-amber border border-amber/20">Urgent</span>}
          {geoBad && <span className="pill bg-red/10 text-red border border-red/20">Geo fail</span>}
          <span className="ml-auto text-[11px] text-txt-muted font-display shrink-0">{fmtMsgTime(r.msg_ts)}</span>
        </div>

        <div className="flex items-center gap-2 text-sm">
          <span className="font-display font-semibold text-txt truncate">{r.sender_name || 'Unknown'}</span>
        </div>

        <div className="flex items-center gap-2 text-xs text-txt-dim">
          <span className="truncate max-w-[42%]">{r.pickup_label?.split(',')[0] || '—'}</span>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#4e5a6e" strokeWidth="2" className="shrink-0">
            <path d="M5 12h14M13 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
          <span className="truncate max-w-[42%]">{r.dropoff_label?.split(',')[0] || '—'}</span>
          <span className="ml-auto text-txt-muted shrink-0">{fmtRideTime(r.ride_time)}</span>
        </div>
      </button>

      {open && (
        <div className="border-t border-border px-3.5 py-3 bg-surface2/40 flex flex-col gap-3">
          <div className="grid grid-cols-2 gap-x-4 gap-y-2.5">
            <Field label="Phone" value={phone
              ? <a href={`https://wa.me/${r.sender_number}`} target="_blank" rel="noreferrer" className="text-accent">{phone}</a>
              : '—'} />
            <Field label="Group" value={r.group_name} />
            <Field label="Pickup" value={r.pickup_label} />
            <Field label="Dropoff" value={r.dropoff_label} />
            <Field label="Ride date" value={r.ride_date} />
            <Field label="Ride time" value={fmtRideTime(r.ride_time)} />
            <Field label="Frequency" value={r.ride_frequency} />
            <Field label="Priority" value={r.important_ride} />
            <Field label="Geo status" value={r.geo_status} />
            <Field label="Conditions" value={r.additional_conditions} />
          </div>
          {r.original_message && (
            <div>
              <div className="text-[9px] uppercase tracking-wide text-txt-muted mb-1">Original message</div>
              <div className="text-xs text-txt-dim whitespace-pre-wrap bg-bg/60 border border-border rounded-lg p-2.5 max-h-40 overflow-auto">
                {r.original_message}
              </div>
            </div>
          )}
          <div className="text-[10px] text-txt-muted">Row #{r.id}</div>
        </div>
      )}
    </div>
  )
}
