# n8n: WhatsApp "BOOK <CODE>" verification

Spec for the n8n workflow (lives outside this repo). Nothing here is built by the site itself.

## What it does

A first-time passenger opens `/j/<code>`, picks pickup / drop-off / seats, and gets a 6-character
code. They tap "Send code on WhatsApp", which opens our bot with the text `BOOK XXXXXX`
pre-filled. This workflow turns that message into a confirmed booking and replies with a link
to their passenger home. The join page polls the claim and redirects on its own once the RPC
below succeeds.

The bot only replies, it never sends first. The passenger messages us first, so every reply
here is inside the free 24 hour window.

## Trigger

Incoming WhatsApp text message where the body matches:

```
/^\s*BOOK\s+([A-Z0-9]{6})\s*$/i
```

Capture group 1 is the code. Anything that does not match is not this workflow (leave it to the
existing bot routing).

Inputs to pull from the incoming message:

- code: capture group 1 (the RPC trims, uppercases and strips spaces itself)
- sender: the sender's WhatsApp id, digits only
- profile name: the WhatsApp profile name if present, otherwise null

## RPC call

`POST {SUPABASE_URL}/rest/v1/rpc/trip_join_verify` with the service-role key, the same way the
workflow already calls `driver_manage_url`:

```
apikey: <SERVICE_ROLE_KEY>
Authorization: Bearer <SERVICE_ROLE_KEY>
Content-Type: application/json
```

Body:

```json
{ "p_verify_code": "K7M4QX", "p_wa_id": "<sender digits>", "p_name": "<profile name or null>" }
```

`trip_join_verify` is executable by `service_role` only. Never call it from the browser and
never put the key in any page.

## Response

Success (first time):

```json
{
  "ok": true,
  "already": false,
  "passenger_url": "https://www.pathfynder.ca/p/<token>?b=<booking id>",
  "booking": { "seats": 1, "pickup_label": "Windsor, ON", "dropoff_label": "Essex, ON" },
  "trip": {
    "origin_label": "Windsor, ON",
    "dest_label": "Essex, ON",
    "schedule_text": "Tue, Sep 30 · 7:30 AM",
    "driver_first_name": "Rahul",
    "seats_left": 2
  },
  "name": "Sam"
}
```

Sending the same code again from the same number returns the same payload with
`"already": true` (safe to retry, no second booking, no second driver notification). The same
code from a different number returns `not_found`.

Failure: `{ "ok": false, "reason": "<reason>" }` with reason one of
`not_found`, `invalid_code`, `expired`, `full`, `missing`.

## Reply templates

Send as a plain WhatsApp text reply to the sender.

| Outcome | Reply |
|---|---|
| `ok` and `already` false | `Ride booked ✅`<br>`<origin_label> → <dest_label>`<br>`<schedule_text> · <seats> seat(s) · Driver <driver_first_name>`<br>`See your booked ride: <passenger_url>` |
| `ok` and `already` true | `You're already booked.` then a blank line, then the same text as above |
| `not_found` or `invalid_code` | `That code isn't valid. Please start again from the ride link.` |
| `expired` | `That code expired. Open the ride link to get a new one.` |
| `full` | `Sorry, that ride just filled up. Find another on https://www.pathfynder.ca/explore` |
| `missing` | no reply needed (means the workflow passed an empty code or sender; fix the mapping) |

Use `seat` when `booking.seats` is 1 and `seats` otherwise. `origin_label`, `dest_label`,
`schedule_text` and `driver_first_name` come from `trip`; `seats` comes from `booking`.
`schedule_text` can be null for odd trips, so drop that segment if it is empty.

Example success reply:

```
Ride booked ✅
Windsor, ON → Essex, ON
Tue, Sep 30 · 7:30 AM · 1 seat · Driver Rahul
See your booked ride: https://www.pathfynder.ca/p/<token>?b=<booking id>
```

## Behaviour notes

- Claims last 30 minutes. A code older than that answers `expired`.
- There is no seat hold: seats are checked when the code is verified. If the ride filled up in
  the meantime the answer is `full`.
- One `passengers` row per verified WhatsApp number. The name is only filled from
  `p_name` when the row has none, so a later profile edit is never overwritten.
- The driver gets the usual "joined your ride" push once, on the first successful verify.
- Never log or echo the sender number or `passenger_url` outside the reply itself.

## Test with curl

Placeholders only. Get a code by starting a claim from the join page (or call the anon RPC
`trip_join_start` with a real join code), then:

```bash
curl -sS "$SUPABASE_URL/rest/v1/rpc/trip_join_verify" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_verify_code":"K7M4QX","p_wa_id":"<test wa id digits>","p_name":"Test Name"}'
```

Expected checks:

1. First call returns `ok: true, already: false`.
2. Same call again returns `ok: true, already: true` with the same `passenger_url`.
3. A made-up code returns `{"ok": false, "reason": "not_found"}`.
4. The join page, still open on the verify screen, redirects to the passenger home within a few
   seconds of the first call.
5. The same request with the anon key instead of the service-role key is rejected (permission
   denied).
