/* ---------------------------------------------------------------------
   Local mock data for /manage (manage.html), matching the
   trip_manage_get / trip_manage_action RPC contract (see plan for
   /m/:token). Loaded only when ?mock=1. In-memory only, per query
   `state` param: draft | active | completed | invalid (adds a trip today
   with that status; no param = no trip today, empty state shows).
   ?fail=1 makes trip_manage_action reject, to test optimistic rollback.
   TODO: delete this file once trip_manage_get / trip_manage_action ship.
   --------------------------------------------------------------------- */
(function (global) {
  var ORIGIN = { lat: 42.3149, lng: -83.0364, label: 'Windsor, ON' };
  var DEST = { lat: 42.1751, lng: -82.8185, label: 'Essex, ON' };
  var LEAMINGTON = { lat: 42.0531, lng: -82.5998 };

  function isoOffset(ms) { return new Date(Date.now() + ms).toISOString(); }
  function clone(o) { return o == null ? o : JSON.parse(JSON.stringify(o)); }

  function buildPayload(stateKey, tripId, departAt, reverse) {
    if (stateKey === 'invalid') return null;

    var tripStatus = stateKey === 'draft' ? 'draft' : (stateKey === 'completed' ? 'completed' : 'active');

    var bookings = [
      { id: 'b1', name: 'Sara', phone: '15195550101', seats: 1,
        pickup_label: 'Peter Street, Windsor, Ontario, Canada', pickup_lat: 42.3178, pickup_lng: -83.0310,
        dropoff_label: 'Essex, Ontario, Canada', dropoff_lat: DEST.lat, dropoff_lng: DEST.lng,
        pickup_time: null, created_at: isoOffset(-3 * 24 * 3600e3), picked_up_at: null, dropped_off_at: null, note: "I'll be waiting by the red door, thanks!" },
      { id: 'b2', name: 'Priya', phone: '15195550102', seats: 1,
        pickup_label: '496 Askin Avenue, Windsor, Ontario N9B 2W8, Canada', pickup_lat: 42.3145, pickup_lng: -83.0655,
        dropoff_label: 'Essex, Ontario, Canada', dropoff_lat: DEST.lat, dropoff_lng: DEST.lng,
        pickup_time: null, created_at: isoOffset(-3 * 24 * 3600e3 + 60e3), picked_up_at: null, dropped_off_at: null, note: null },
      { id: 'b3', name: 'Amit', phone: '15195550103', seats: 1,
        pickup_label: '496 Askin Avenue, Windsor, Ontario N9B 2W8, Canada', pickup_lat: 42.3145, pickup_lng: -83.0655,
        dropoff_label: 'Leamington, Ontario, Canada', dropoff_lat: LEAMINGTON.lat, dropoff_lng: LEAMINGTON.lng,
        pickup_time: null, created_at: isoOffset(-3 * 24 * 3600e3 + 120e3), picked_up_at: null, dropped_off_at: null, note: 'Near the bus stop' },
      { id: 'b4', name: 'Jordan', phone: '15195550104', seats: 1,
        pickup_label: 'Ottawa Street, Windsor, Ontario, Canada', pickup_lat: 42.3080, pickup_lng: -83.0065,
        dropoff_label: 'Leamington, Ontario, Canada', dropoff_lat: LEAMINGTON.lat, dropoff_lng: LEAMINGTON.lng,
        pickup_time: null, created_at: isoOffset(-3 * 24 * 3600e3 + 180e3), picked_up_at: null, dropped_off_at: null, note: null }
    ];

    if (stateKey === 'active') {
      bookings[3].picked_up_at = isoOffset(-15 * 60e3); /* Jordan already on board */
    } else if (stateKey === 'completed') {
      bookings.forEach(function (b) { b.picked_up_at = isoOffset(-40 * 60e3); b.dropped_off_at = isoOffset(-10 * 60e3); });
    }

    return {
      trip: {
        id: tripId || 'trip-mock', status: tripStatus, driver_name: 'Test Driver',
        origin_label: (reverse ? DEST : ORIGIN).label, origin_lat: (reverse ? DEST : ORIGIN).lat, origin_lng: (reverse ? DEST : ORIGIN).lng,
        dest_label: (reverse ? ORIGIN : DEST).label, dest_lat: (reverse ? ORIGIN : DEST).lat, dest_lng: (reverse ? ORIGIN : DEST).lng,
        depart_at: departAt || '2026-09-24T18:30:00', seats_total: 4, price_per_seat: 10,
        join_url: 'https://pathfynder.ca/j/DEMO42'
      },
      bookings: bookings
    };
  }

  var STORE = {};
  var lastTripId = null;
  function rawState() {
    try { return new URLSearchParams(location.search).get('state'); }
    catch (e) { return null; }
  }
  function shouldFail() {
    try { return new URLSearchParams(location.search).get('fail') === '1'; }
    catch (e) { return false; }
  }
  function dayAt(off, hh, mm) {
    var d = new Date(); d.setHours(hh == null ? 18 : hh, mm == null ? 30 : mm, 0, 0); d.setDate(d.getDate() + off);
    return d.toISOString();
  }
  /* Trip list relative to today: -4/-3/-2 completed, +2 upcoming (draft).
     ?state=draft|active|completed additionally adds a trip today. */
  function tripDefs() {
    var defs = [
      { id: 'trip-m4', off: -4, key: 'completed' },
      { id: 'trip-m3', off: -3, key: 'completed' },
      { id: 'trip-m2', off: -2, key: 'completed' },
      { id: 'trip-p2', off: 2, key: 'draft' },
      { id: 'trip-p2b', off: 2, key: 'draft', hh: 21, mm: 0, reverse: true } /* second trip same day, Essex -> Windsor */
    ];
    var raw = rawState();
    if (raw === 'draft' || raw === 'active' || raw === 'completed') defs.push({ id: 'trip-today', off: 0, key: raw });
    defs.sort(function (a, b) { return (a.off - b.off) || ((a.hh == null ? 18 : a.hh) - (b.hh == null ? 18 : b.hh)); });
    return defs;
  }
  function findDef(id) {
    var defs = tripDefs();
    for (var i = 0; i < defs.length; i++) if (defs[i].id === id) return defs[i];
    return null;
  }
  function getStore(id) {
    var def = findDef(id);
    if (!def) return null;
    if (!(id in STORE)) STORE[id] = buildPayload(def.key, id, dayAt(def.off, def.hh, def.mm), def.reverse);
    return STORE[id];
  }

  global.PF_MANAGE_MOCK = {
    list: function () {
      return new Promise(function (resolve) {
        setTimeout(function () {
          if (rawState() === 'invalid') { resolve({ error: 'invalid_token' }); return; }
          resolve({ trips: tripDefs().map(function (d) {
            var st = STORE[d.id];
            return { id: d.id, depart_at: dayAt(d.off, d.hh, d.mm), status: st ? st.trip.status : d.key,
              origin_label: (d.reverse ? DEST : ORIGIN).label, dest_label: (d.reverse ? ORIGIN : DEST).label };
          }) });
        }, 200);
      });
    },
    get: function (token, tripId) {
      return new Promise(function (resolve) {
        setTimeout(function () {
          if (rawState() === 'invalid') { resolve({ error: 'invalid_token' }); return; }
          lastTripId = tripId;
          var st = getStore(tripId);
          resolve(st ? clone(st) : { error: 'invalid_token' });
        }, 300);
      });
    },
    action: function (token, action, bookingId, tripId) {
      return new Promise(function (resolve, reject) {
        setTimeout(function () {
          if (shouldFail()) { reject(new Error('mock action failure')); return; }
          var st = getStore(tripId || lastTripId);
          if (!st) { resolve({ error: 'invalid_token' }); return; }
          var now = new Date().toISOString();
          /* Mirror server rule: pickup/dropoff only while the trip is started and not ended. */
          if ((action === 'picked_up' || action === 'dropped_off') && st.trip.status !== 'active') { resolve({ error: 'not_started' }); return; }
          if (action === 'start') st.trip.status = 'active';
          else if (action === 'end') st.trip.status = 'completed';
          else if (action === 'remove') st.bookings = st.bookings.filter(function (b) { return b.id !== bookingId; });
          else if (action === 'picked_up') st.bookings.forEach(function (b) { if (b.id === bookingId) b.picked_up_at = now; });
          else if (action === 'dropped_off') st.bookings.forEach(function (b) { if (b.id === bookingId) b.dropped_off_at = now; });
          resolve(clone(st));
        }, 300);
      });
    }
  };
})(window);
