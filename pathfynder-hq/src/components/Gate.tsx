import { useState } from 'react'

export default function Gate({ onPass }: { onPass: () => void }) {
  const [pw, setPw] = useState('')
  const [err, setErr] = useState(false)
  const expected = import.meta.env.VITE_DASHBOARD_PASSCODE

  const submit = () => {
    if (pw && pw === expected) onPass()
    else setErr(true)
  }

  return (
    <div className="min-h-screen flex items-center justify-center px-4"
      style={{ background: 'radial-gradient(ellipse at 50% 40%, rgba(79,142,247,.08), transparent 70%)' }}>
      <div className="card border-border2 w-full max-w-[340px] p-10 text-center"
        style={{ boxShadow: '0 0 60px rgba(79,142,247,.06)' }}>
        <div className="w-13 h-13 bg-accent rounded-2xl mx-auto mb-4 flex items-center justify-center"
          style={{ width: 52, height: 52 }}>
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2.2"
            strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="9" /><path d="M12 3v3M12 18v3M3 12h3M18 12h3" />
            <circle cx="12" cy="12" r="2.5" fill="#fff" stroke="none" />
          </svg>
        </div>
        <div className="font-display text-2xl font-bold">Pathfynder</div>
        <div className="text-xs text-txt-muted mb-7">Founder HQ · restricted access</div>
        <input
          type="password" value={pw} autoComplete="off" placeholder="Enter passphrase"
          onChange={(e) => { setPw(e.target.value); setErr(false) }}
          onKeyDown={(e) => e.key === 'Enter' && submit()}
          className="w-full py-3 px-4 bg-surface2 border border-border2 rounded-xl text-txt text-center tracking-[3px] outline-none focus:border-accent mb-3 placeholder:tracking-normal placeholder:text-txt-muted"
        />
        <button onClick={submit}
          className="w-full h-11 bg-accent rounded-xl text-white font-display font-semibold active:opacity-85">
          Enter
        </button>
        {err && <div className="text-red text-xs mt-3">Incorrect passphrase</div>}
      </div>
    </div>
  )
}
