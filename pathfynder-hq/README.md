# Pathfynder — Founder HQ (v2)

Live admin dashboard for ride messages scraped from WhatsApp groups into Supabase.
React + TypeScript + Vite + Tailwind. All times shown in **America/Toronto**;
data is stored in UTC and converted on the client.

## Run locally (VS Code)

```bash
npm install
npm run dev
```

Open http://localhost:5173/admin.html — the passphrase is the dashboard passphrase, checked server-side (see below).

## Environment

Copy `.env.example` to `.env` and fill in (a working `.env` is already included):

| Var | Meaning |
|-----|---------|
| `VITE_SUPABASE_URL` | Supabase project URL |
| `VITE_SUPABASE_ANON_KEY` | Anon key (public-safe; table is RLS-guarded, read-only) |

`.env` is gitignored. The passphrase is checked server-side: the gate calls the `hq_check` RPC
(hash compared against `dashboard_auth`), and `get_feed` / `get_power_users` require `p_pass`
and raise `unauthorized` without it. The passphrase is kept in `sessionStorage` for the tab only.

## Features

- **Date filter (Toronto)** — Today / 7d / 30d / All + custom range. Drives KPIs, feed, trend.
- **KPI strip** — messages, passengers, drivers, pax/driver, active groups, urgent %, geocode %.
- **Ride feed** — Live (auto-refresh 15s), Today, Past (uses date filter). Search + type filter,
  server-side pagination, tap any card for full per-person detail (phone→WhatsApp link, group,
  route, ride date/time, priority, geo status, raw message).
- **Insights** — daily volume trend, top corridors, busiest groups.

## Backend (already applied to Supabase)

Three read-only RPCs power the app:
- `get_feed(p_start, p_end, p_type, p_search, p_limit, p_offset)` — paginated feed by UTC window.
- `get_window_stats(p_start, p_end)` — KPI aggregates.
- `get_daily_series(p_start, p_end)` — per-Toronto-day counts for the trend chart.

The client filters on `"D&T of msg"` (reliable UTC message time), **not** `"pick up date"`,
which has a known extractor bug (asap/now → year 2023). Ride date/time is shown as detail only.

## Build

```bash
npm run build     # tsc + vite build → dist/
npm run preview   # serve the production build
```
