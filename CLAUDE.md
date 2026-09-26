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
- The browser NEVER queries tables directly. Only RPCs via supabase.rpc().
- Never render raw phone numbers. Names = first name + last initial.
- Search RPC (being built): explore_search(p_mode, p_o_lat, p_o_lng, p_d_lat, p_d_lng, p_date, p_filters jsonb) returns rows:
  id, source ('whatsapp'|'poparide'|'facebook'), role ('driver'|'passenger'), display_name, origin_label, dest_label, ride_date, ride_time, arrive_time, seats, price, rating, rating_count, verified, luggage, recurring_label, posted_count, is_business, is_coordinator, is_regular, match_type ('direct'|'along_route'), pickup_km, dropoff_km, score, description
- Contact: WhatsApp rows → call explore_contact(id) on tap, it returns a wa.me link with a prefilled message; Poparide/Facebook rows → it returns the external URL. Never preload contacts in the list.
- From/To autocomplete: read the public `places` table (name, lat, lng) — no paid geocoding.
- Until explore_search exists, build against a local mock file with this exact shape.

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
