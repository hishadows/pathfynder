/* ---------------------------------------------------------------------
   Local mock data for /j/<code> (join.html), matching the proposed
   trip_join_get / trip_join RPC contract (design/trip-join-rpcs.sql).
   Loaded only when ?mock=1. In-memory only. Query params:
     state=open (default) | full | invalid | expired
     returning=1   pretend name + WhatsApp are saved on this device
     fail=1        trip_join rejects (RPC error path)
     race=1        trip_join answers "full" (seat taken while booking)
     notoken=1     trip_join returns no passenger_token (temporary "Seat confirmed" fallback)
   TODO: delete this file once trip_join_get / trip_join ship.
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
      code: code, status: full ? 'full' : 'open',
      driver_first_name: 'Rahul', round_trip: true, title: 'Windsor to Essex daily commute',
      origin_label: 'Windsor, ON', dest_label: 'Essex, ON', stops_count: 2,
      schedule_text: 'Mon, Tue, Wed, Thu, Fri · 7:30 AM out · 5:15 PM back',
      price_per_seat: 10, seats_total: 4, seats_left: full ? 0 : 3, joined_count: full ? 4 : 1
    } };
  }

  global.PF_JOIN_MOCK = {
    places: function (q) {
      var n = String(q || '').toLowerCase();
      return Promise.resolve(PLACES.filter(function (p) { return p.name.toLowerCase().indexOf(n) === 0; }).map(clone));
    },
    get: function (code) {
      return new Promise(function (resolve) { setTimeout(function () { resolve(trip(code || 'DEMO42')); }, 250); });
    },
    join: function (a) {
      return new Promise(function (resolve, reject) {
        setTimeout(function () {
          if (qp('fail') === '1') { reject(new Error('mock join failure')); return; }
          var t = trip(a.p_code || 'DEMO42');
          if (t.error) { resolve(t); return; }
          if (qp('race') === '1' || t.trip.seats_left < a.p_seats) { resolve({ error: 'full' }); return; }
          t.trip.seats_left -= a.p_seats; t.trip.joined_count += 1;
          resolve({ booking: { id: 'bk-mock', seats: a.p_seats, status: 'confirmed', pickup_label: a.p_pickup.label, dropoff_label: a.p_dropoff.label }, trip: t.trip, passenger_token: qp('notoken') === '1' ? null : 'mock' });
        }, 350);
      });
    }
  };
})(window);
