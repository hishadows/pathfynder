## Project
Pathfynder (Pathfynder Car Pool Inc., Ontario) — community rideshare. This repo = public site pathfynder.ca. The dispatch app (app.pathfynder.ca) and Telegram mini app (pathfynder-form) are separate repos — never edit them from here.
Supabase project: omussxfyrztjahbdrrpi (PostGIS in `extensions` schema). Supabase MCP here is READ-ONLY; schema/RPC changes are done outside this repo.

## Current feature: /explore (Explore Rides)
Public page, linked from WhatsApp groups + WhatsApp bot. WhatsApp look (light + dark, follow system):
Light: header #008069, CTA #25D366, bg #F0F2F5, cards #FFFFFF, text #111B21, secondary #667781, dividers #E9EDEF, soft chip #D9FDD3
Dark: bg #0B141A, header/cards #202C33, surface #111B21, text #E9EDEF, secondary #8696A0, accent #00A884, dividers #2A3942
Mobile-first 390px, desktop centered column max 720px. System font stack.
Deep link params: ?mode=drivers|passengers&from=&to=&date=YYYY-MM-DD — page opens pre-filled.

## Data rules (strict)
- The browser NEVER queries tables directly except the public `places` table (autocomplete). Everything else goes through RPCs via supabase.rpc().
- Never render raw phone numbers. Names = first name + last initial (display_name is already formatted server-side).
- Search RPC: explore_search(p_mode, p_o_lat, p_o_lng, p_d_lat, p_d_lng, p_date, p_filters jsonb)
  - p_mode: 'drivers' (Find a driver) | 'passengers' (Find passengers)
  - p_date: 'YYYY-MM-DD'; null = today + next 3 days
  - p_filters (omit unset keys, never send false/empty arrays): sources (array of 'whatsapp'|'poparide'|'facebook', default all three), match ('direct' when set), time_of_day (array of 'morning'|'afternoon'|'evening'|'night'), time ('HH:MM') + flex_min (0|15|30|60|120), urgent / airport / daily / verified_only / hide_business / luggage_ok (booleans), from_name / to_name (selected place names, for matching unparsed Facebook posts)
  - Returns rows already ranked (parsed first, business last, direct before along_route, then score): id, source ('whatsapp'|'poparide'|'facebook'), role ('driver'|'passenger'), parsed, display_name, origin_label, dest_label, ride_date (nullable — undated Facebook posts), ride_time, arrive_time, seats, price (formatted text, e.g. "$25 CAD" — never render with a prepended "$"), price_num (the number to actually display/sort on), rating, rating_count, verified, luggage, recurring_label, posted_count, is_urgent, is_airport, is_daily, groups (jsonb [{name, posted_at}]), posted_at, is_business, is_coordinator, is_regular, match_type ('direct'|'along_route'), pickup_km, dropoff_km, score, description, raw_text
  - "Soonest" = ride_date asc then ride_time asc (nulls last); "Cheapest" = price_num asc (nulls last, ties broken by Soonest order). Both sorted client-side; "Best match" keeps the RPC's own order (stable sort, no reorder).
  - Route strip fields (detail sheet, driver mode, along_route only, may not always be present): route_km, pickup_pct, dropoff_pct.
- Contact: every CTA calls explore_contact(p_id) on tap. WhatsApp rows → contact_type 'whatsapp', open the returned wa.me url with a prefilled message in the current tab; Poparide/Facebook rows → contact_type 'external', open the returned url in a new tab (the popup is opened synchronously in the tap handler, before the RPC's await, and redirected once the URL is known — mobile browsers block window.open() called after an await). Errors: 'rate_limited' / 'not_available' → toast, no number/URL ever preloaded in the list.
- Group link submission RPC: submit_group_link({ p_url, p_from, p_to }) → { status: 'ok'|'duplicate'|'invalid'|'rate_limited', message }. Used by the "Know a WhatsApp ride group for this route?" card shown when the current results have 0 whatsapp rows; ok/duplicate collapses the card and hides it for 7 days (localStorage `pf_group_card_done`).
- From/To autocomplete + deep-link resolution: `places` table first (name, province, lat, lng), always. Autocomplete uses the Mapbox Search Box API (suggest + retrieve, one session token per input rotated after each retrieve, min 3 chars, 300ms debounce, AbortController) — Mapbox POIs/addresses/cities show first (up to 6) then up to 3 `places` rows not already present, deduped by name. Deep-link resolution only falls through to one suggest+retrieve call when `places` finds nothing. Mapbox is skipped entirely (silent places-only fallback) when `MAPBOX_TOKEN` is empty or the request fails/401/403/429. No paid geocoding beyond that.
- From-only search: picking a From place (with or without a To) runs a search immediately — near-from (`p_o_lat/lng` set, `p_d_*` null) until To is also picked, then matched. Clearing To returns to near-from; clearing From returns to browse/near-me.
- Location: no popups/sheets, ever. Geolocation is silent when already granted; otherwise driven only by the inline "Use my location" card, which shows the result (near-me search / blocked-with-steps / denied) in place.
- explore_search doesn't exist in prod yet — explore.html falls back to explore-mock.js (same row shape) when the RPC call errors with "does not exist" (42883). Delete that fallback + explore-mock.js once the RPC ships.
- `?debug=1` on the URL logs every explore_search payload and returned row count to the console.

## Working rules
- Surgical, line-level edits. Never rewrite whole files unless asked.
- New versions of standalone pages use versioned filenames (e.g. explore-v2.html) if the repo uses plain HTML pages.
- Pranay commits and pushes himself — never run git commit/push.
- For bugs: show the exact file + line causing it before proposing a fix.
- Keep pathfynder-changelog.md updated for functional changes (date, what, files).
- Verification: UI-only → no build needed. Logic → type check/lint only if the repo has it. Build/config/deps → run the build.

## Repo layout (for reference)
- Root: static HTML site deployed by Vercel (`vercel.json`) — `index.html` (landing), `dashboard.html`, `logo.png`. These are plain HTML with inline `<style>` using CSS custom properties (`--bg`, `--card`, `--teal`, `--indigo`, `--text`, `--muted`), dark theme by default with a light override block — not Tailwind.
- `pathfynder-hq/`: separate React + Vite + TypeScript app (the admin dashboard, entry `admin.html` / `src/App.tsx`). Uses Tailwind with its own dark-only palette (`bg #080c14`, `surface #0f1420`, `accent #4f8ef7`, fonts Space Grotesk/Inter) — a different design system from the root static pages.
- Supabase client lives at `pathfynder-hq/src/lib/supabase.ts`, reading `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY` from `.env` (see `pathfynder-hq/.env.example`); session persistence is disabled.
- Vercel build: `cd pathfynder-hq && npm install && npm run build`, then copies `pathfynder-hq/dist/*` plus the root static HTML/PNG files into `public/` (the output dir).
