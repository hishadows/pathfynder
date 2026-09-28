# Pathfynder plan

One task per session. Status: todo / done / parked.

1. **Explore: reliable results + silent location** — fix false "Couldn't load rides" (supersede/abort handling, per-row try/catch), remove all location-asking UI, silent geolocation that never blocks results, reverse-geocode the full address into From (Mapbox Geocoding v6 reverse).
   - Done when: results always render with or without location, no location prompts/cards exist, and a granted location fills From with the full address.
   - Status: done (2026-09-27)

2. **Explore: group-link card on every zero-results screen** — including links opened from the bot with date/time/flex params; remove the 7-day suppression.
   - Done when: any zero-results screen (incl. a bot link with date/time/flex) shows the empty message + group-link card, even after a previous submit.
   - Status: done (2026-09-27)

3. **Explore: `o=lat,lng` / `d=lat,lng` URL params** — use the coords directly, skip place lookup, write them back to the URL.
   - Done when: `/explore?from=A&to=B&o=..&d=..` searches without a places/Mapbox lookup and the URL keeps `o`/`d` after edits.
   - Status: done (2026-09-26)

4. **Landing: WhatsApp bot buttons above Telegram** (hero + CTA section).
   - Done when: in both the hero and the CTA section the WhatsApp bot button comes before the Telegram one.
   - Status: done (already in index.html — hero and CTA list WhatsApp first; no changelog entry). Header nav CTA is still "Join on Telegram".

5. **DB: trips + bookings** — one trip per source ride (unique), join code + private manage token, RPCs `trip_manage_get` / `trip_manage_action`. Plan the schema first and ask Pranay before applying.
   - Done when: schema plan approved, migration applied, both RPCs callable by anon with only token/code access.
   - Status: todo

6. **Driver manage page `/m/<token>`** — built from the Claude Design file in `design/`.
   - Done when: `/m/<token>` loads the trip via `trip_manage_get` and actions work via `trip_manage_action`.
   - Status: done against mock (2026-09-28) — built from Pranay's screenshot, not `design/`; goes live once task 5 ships the RPCs

7. **Passenger join page `/j/<code>`** — pickup, drop-off, time, "for work" toggle + shift start, note, "Confirm on WhatsApp".
   - Done when: `/j/<code>` shows the trip and "Confirm on WhatsApp" opens WhatsApp with the filled-in details.
   - Note (2026-09-28): no driver approval step — joining books the seat immediately (confirmed); the join must refuse when seats are full. Page not designed yet; the manage page's Share link already points to it (`trip.join_url`).
   - Status: todo (needs task 5)

8. **PWA** — manifest, service worker, install prompt, Web Push opt-in. Plan first.
   - Done when: the app installs on Android + iOS, an install prompt shows where supported, and push opt-in works from Explore.
   - Status: todo (partly exists: dynamic manifest, `sw.js` push-only, push opt-in via `/notifications` + `js/pf-notify-v4.js`; no install prompt yet)

9. **Security: lock anon reads of `extracted_data_01`.**
   - Done when: anon can no longer select from `extracted_data_01` and the Telegram mini app still works.
   - Status: parked (the Telegram mini app depends on it)

10. **Notifications: iPhone "Add to Home Screen" pop-up** — when someone on iPhone Safari taps "Turn on notifications", show a polished bottom sheet: notifications only work once Pathfynder is added to the Home Screen, with step-by-step iPhone instructions. Not shown on Android (push works in Chrome) or inside the installed app.
   - Done when: on iPhone outside the installed app, "Turn on notifications" opens the sheet; Android and the installed app keep the old flow; looks right in light + dark at 390px and closes cleanly.
   - Status: done (2026-09-27)

## Session notes

- 2026-09-27 — Setup: rewrote CLAUDE.md (short, general facts only) and created plan.md. Open: task 4 was already done in index.html but has no changelog entry; header nav still says "Join on Telegram".
- 2026-09-27 — Task 10: new `js/pf-install-sheet-v1.js` bottom sheet, opened from Explore's "Turn on notifications" on iPhone Safari and from a "Show me how" button on /notifications. Open: not yet checked on a real iPhone (Playwright emulation only).
- 2026-09-27 — Bug: live location ignored on /explore — stale `pf_geo_failed` flag from any past GPS timeout blocked it forever. Now only a real denial is remembered, granted permission clears it, and enabling location mid-session triggers near-me. Open: not yet checked on a real phone.
- 2026-09-27 — Follow-up: Safari still ignored location (reports permission as `prompt`, so stale `pf_geo_failed` never cleared). Switched denial memory to new key `pf_geo_denied`; old key removed on load. Open: confirm on Pranay's iPhone Safari after deploy.
- 2026-09-27 — Notifications for all Explore visitors: tokenless devices get an `ALERTS <code>` WhatsApp link step (`notify_link_device`). Open: n8n bot step for `ALERTS <code>` not added yet — do not merge/deploy the front end until it is; real-phone test pending.
- 2026-09-28 — Task 6: new `manage.html` + `manage-mock.js` (`?mock=1&state=not_started|in_progress|ended|invalid`, `&fail=1`), `/m/:token` rewrite, build.sh copy. `docs/booking-flow.md` was missing, so the data contract is the one in the changelog entry. Open: RPCs `trip_manage_get`/`trip_manage_action` don't exist yet (task 5); real-phone test pending.
- 2026-09-28 — Explore card UI cleanup (ad-hoc, from Pranay's screenshot): top-row tags wrap instead of overlapping ("Needs ride" is now a tag, time reads "3d ago"), more space between/inside cards + light shadow, punctuation-only names show "WhatsApp member" with a person avatar. Open: check on Pranay's iPhone after deploy.
- 2026-09-28 — Manage ride v2: requests/approval removed (joining = confirmed), trip status draft/active/completed, picked_up_at/dropped_off_at timestamps, Cash to collect card, Open in Maps rebuilt to Pranay's production spec (GPS origin, 150 m dedupe, exact shortest order, label URLs, PWA/desktop open). Open: RPCs still missing (task 5); real-phone Maps test pending.
- 2026-09-28 — Removed the Cash to collect card from the manage page (Pranay's call).
- 2026-09-28 — Calmer WhatsApp buttons on Explore: cards use a soft mint pill (`.btn--wa-soft`), the detail sheet and notifications keep a solid but deep green (#008069 light / #005C4B dark); WhatsApp logo icon replaces the chat bubble. Open: check on iPhone after deploy.
- 2026-09-28 — Manage ride page (`manage.html`): main buttons now use the same calm deep green as Explore (#008069 light / #005C4B dark, hover #006D5B); WhatsApp logo on "Message us on WhatsApp". Hero seat-progress bar left bright on purpose. Open: check on iPhone after deploy.
- 2026-09-28 — Manage ride layout rework: bottom bar is "Invite passengers" + Start trip → End trip (both confirm); "Full route in Maps" card under the hero; passenger cards drop price/seats/status tag, get a WhatsApp contact button, "Remove passenger" before start (pop-up nudges the driver to message them first), I'm outside/Picked up only after start. Open: real-phone test pending.
- 2026-09-28 — Manage page: "Your route" hero slide now on a white card (dark mode: #202C33 card), green start/destination dots.
