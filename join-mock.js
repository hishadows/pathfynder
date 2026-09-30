/* ---------------------------------------------------------------------
   Local mock data for /j/<code> (join.html), matching the proposed
   trip_join_get / trip_join / trip_join_start / trip_join_claim_status RPC contract
   (design/trip-join-rpcs-live.sql, design/trip-join-verify-rpcs.sql).
   Loaded only when ?mock=1. In-memory only. Query params:
     state=open (default) | full | invalid | expired
     returning=1   pretend a passenger token is saved on this device (direct booking via trip_join)
     stale=1       with returning=1: trip_join answers verification_required (stale token -> first-time flow)
     verify=never (default) | auto | expired | full
                   what the WhatsApp verification does ~4s after the code is issued:
                   stays pending | verified (redirects to the passenger home) | claim expires | ride filled up
     fail=1        trip_join / trip_join_start reject (RPC error path)
     race=1        trip_join / trip_join_start answer "full" (seat taken while booking)
     notoken=1     trip_join returns no passenger_token (temporary "Seat confirmed" fallback)
   TODO: delete this file once the live RPCs are wired everywhere.
   --------------------------------------------------------------------- */
(function (global) {
  function qp(k) { try { return new URLSearchParams(location.search).get(k); } catch (e) { return null; } }
  function clone(o) { return o == null ? o : JSON.parse(JSON.stringify(o)); }

  var PLACES = [
    { name: 'Windsor', sub: 'ON', label: 'Windsor, ON, Canada', lat: 42.3149, lng: -83.0364 },
    { name: 'Essex', sub: 'ON', label: 'Essex, ON, Canada', lat: 42.1751, lng: -82.8185 },
    { name: 'Leamington', sub: 'ON', label: 'Leamington, ON, Canada', lat: 42.0531, lng: -82.5998 },
    { name: 'Kingsville', sub: 'ON', label: 'Kingsville, ON, Canada', lat: 42.0392, lng: -82.7435 },
    { name: 'Tecumseh', sub: 'ON', label: 'Tecumseh, ON, Canada', lat: 42.3117, lng: -82.8998 },
    { name: 'London', sub: 'ON', label: 'London, ON, Canada', lat: 42.9849, lng: -81.2453 }
  ];

  function trip(code) {
    var st = qp('state') || 'open';
    if (st === 'invalid') return { error: 'invalid_code' };
    if (st === 'expired') return { error: 'expired' };
    var full = st === 'full';
    return { trip: {
      code: code, driver_id: '7d2e9b40-0002-4b00-8000-00000000d002', status: full ? 'full' : 'open',
      driver_first_name: 'Rahul', round_trip: true, title: 'Windsor to Essex daily commute',
      message_url: qp('nomsg') ? null : 'https://wa.me/15550000000?text=Hi%20Rahul', // mock only; live RPC builds it (no raw phone); ?nomsg=1 omits it
      origin_label: 'Windsor, ON', dest_label: 'Essex, ON', stops_count: 2,
      schedule_text: 'Mon, Tue, Wed, Thu, Fri · 7:30 AM out · 5:15 PM back',
      price_per_seat: 10, seats_total: 4, seats_left: full ? 0 : 3, joined_count: full ? 4 : 1
    } };
  }

  var CLAIMS = {}, claimSeq = 0, lastCode = '';
  var VERIFY_MS = 4000;
  function genCode() {
    var al = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789', c;
    do { c = ''; for (var i = 0; i < 6; i++) c += al.charAt(Math.floor(Math.random() * al.length)); } while (c === lastCode);
    lastCode = c; return c;
  }

  global.PF_JOIN_MOCK = {
    places: function (q) {
      var n = String(q || '').toLowerCase();
      return Promise.resolve(PLACES.filter(function (p) { return p.name.toLowerCase().indexOf(n) === 0; }).map(clone));
    },
    get: function (code) {
      return new Promise(function (resolve) { setTimeout(function () { resolve(trip(code || 'DEMO42')); }, 250); });
    },
    start: function (a) {
      return new Promise(function (resolve, reject) {
        setTimeout(function () {
          if (qp('fail') === '1') { reject(new Error('mock start failure')); return; }
          var t = trip(a.p_code || 'DEMO42');
          if (t.error) { resolve(t); return; }
          if (qp('race') === '1' || t.trip.seats_left < a.p_seats) { resolve({ error: 'full' }); return; }
          var id = 'claim-mock-' + (++claimSeq), now = Date.now(), mode = qp('verify') || 'never';
          CLAIMS[id] = { at: now, mode: mode, trip: t.trip };
          resolve({ claim_id: id, verify_code: genCode(), trip: t.trip,
            expires_at: new Date(now + (mode === 'expired' ? VERIFY_MS : 30 * 60000)).toISOString() });
        }, 350);
      });
    },
    claimStatus: function (id) {
      return new Promise(function (resolve) {
        setTimeout(function () {
          var c = CLAIMS[id];
          if (!c) { resolve({ status: 'failed' }); return; }
          var due = Date.now() - c.at >= VERIFY_MS;
          if (due && c.mode === 'auto') resolve({ status: 'verified', passenger_token: 'mock', booking_id: 'bk-mock', trip: c.trip });
          else if (due && c.mode === 'expired') resolve({ status: 'expired', trip: c.trip });
          else if (due && c.mode === 'full') resolve({ status: 'full', trip: c.trip });
          else resolve({ status: 'pending', trip: c.trip });
        }, 150);
      });
    },
    join: function (a) {
      return new Promise(function (resolve, reject) {
        setTimeout(function () {
          if (qp('fail') === '1') { reject(new Error('mock join failure')); return; }
          var t = trip(a.p_code || 'DEMO42');
          if (t.error) { resolve(t); return; }
          if (!a.p_passenger_token || qp('stale') === '1') { resolve({ error: 'verification_required' }); return; }
          if (qp('race') === '1' || t.trip.seats_left < a.p_seats) { resolve({ error: 'full' }); return; }
          t.trip.seats_left -= a.p_seats; t.trip.joined_count += 1;
          resolve({ booking: { id: 'bk-mock', seats: a.p_seats, status: 'confirmed', pickup_label: a.p_pickup.label, dropoff_label: a.p_dropoff.label }, trip: t.trip, passenger_token: qp('notoken') === '1' ? null : 'mock' });
        }, 350);
      });
    }
  };
})(window);
