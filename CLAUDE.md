## Project
Pathfynder (pathfynder.ca) — community rideshare for Ontario (Pathfynder Car Pool Inc.).
Public pages are plain HTML with inline CSS/JS, deployed on Vercel (`cleanUrls`). No framework, no build step for these pages.
The dispatch app (app.pathfynder.ca) and the Telegram mini app (pathfynder-form) are separate repos — never edit them from here.

## File map
- `index.html` — landing page
- `explore.html` — Explore Rides (`explore-mock.js` = mock data, used with `?mock=1`)
- `vercel.json` — Vercel config (cleanUrls, `/r/:code` rewrite)
- `design/` — mockups (reference only)
- `plan.md` — backlog + session notes
- `pathfynder-changelog.md` — changelog
- Also present: `notifications.html`, `manifest.webmanifest`, `sw.js`, `js/pf-notify-v*.js`, `icons/`, `api/` (Vercel functions: `r.js`, `manifest.js`), `build.sh`, `pathfynder-hq/` (separate React admin app), `dashboard.html`.
- `build.sh` copies root files into `public/` by explicit name — a new root HTML/JS file must be added there to be deployed.

## Supabase
- Project `omussxfyrztjahbdrrpi`; PostGIS lives in the `extensions` schema.
- Key RPCs: `explore_search`, `explore_contact`, `submit_group_link`, `landing_stats`, `bot_match_reply_for`.
- Tables: `extracted_data_01` (WhatsApp posts), `muse_ride_posts` (Poparide/FB), `passenger_requests`, `driver_routines`.
- The browser goes through RPCs only (`supabase.rpc()`), except the public `places` table for autocomplete.
- DB reads via `execute_sql`; schema changes via `apply_migration`. To change a PostGIS function: DROP, then CREATE.

## WhatsApp bot
- +916356600421, runs on n8n (outside this repo).
- The bot only replies, never sends first (free tier). Notifications come from the PWA.

## Design tokens
- Explore — WhatsApp palette, light + dark (follow system):
  - Light: header #008069, CTA #25D366, bg #F0F2F5, cards #FFFFFF, text #111B21, secondary #667781, dividers #E9EDEF
  - Dark: bg #0B141A, header/cards #202C33, surface #111B21, text #E9EDEF, secondary #8696A0, accent #00A884, dividers #2A3942
- Driver pages — pine #0F5C43 / #163C32, bg #EEF0EC.
- Mobile-first (390px), system font stack.

## Working rules
- Before making any change, first write a short plan (files to touch, what changes, how I'll test it) and wait for Pranay's "yes". Only then build it.
- Workflow: you (main model) plan and review only. After I say yes, delegate the whole implementation to the builder subagent, passing the full approved plan plus the relevant file paths and the spec file. When builder reports back, review its changes briefly, then tick plan.md and update the changelog.
- Mobile-first.
- Surgical, line-level edits only. Never rewrite whole files unless asked.
- One task at a time from `plan.md`. After finishing, add 1–3 lines under "Session notes" in `plan.md`.
- Read only the files the task needs.
- Plain HTML has no tsc/build — verify inline JS with `node --check` on the extracted script.
- Update `pathfynder-changelog.md` after functional changes (date, what, files).
- Git: in cloud sessions, commit and push to the session's `claude/*` branch after each finished task. Never push to `main` directly. When Pranay says "merge", open a PR from the `claude/*` branch and merge it into `main`.
- When a requirement is unclear, ask instead of guessing.
- For bugs: show the exact file + line causing it before fixing.
- Never render raw phone numbers.
