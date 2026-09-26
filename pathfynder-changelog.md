# Pathfynder Changelog

- 2026-09-26 — Added CLAUDE.md (project + /explore rules)
- 2026-09-26 — Built /explore (Explore Rides) page from design/explore-mockup.html v3: search panel, filters sheet, exact-time sheet, ride cards + detail sheet, swipe-to-original-message, empty/loading/error states. Wired to Supabase (`places` autocomplete, `explore_search`/`explore_contact` RPCs) with a local mock fallback (explore-mock.js) until explore_search ships. Files: explore.html, explore-mock.js, vercel.json (cleanUrls + build copy), CLAUDE.md (final RPC contract).
