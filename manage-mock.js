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

  function buildPayload(stateKey, tripId, departAt, reverse, empty) {
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
        pickup_time: null, created_at: isoOffset(-3 * 24 * 3600e3 + 180e3), picked_up_at: null, dropped_off_at: null, note: null },
      /* Picked up at the driver's origin (Windsor) */
      { id: 'b5', name: 'Pranay', phone: '15195550105', seats: 1,
        pickup_label: 'Windsor, Ontario, Canada', pickup_lat: ORIGIN.lat, pickup_lng: ORIGIN.lng,
        dropoff_label: 'Leamington, Ontario, Canada', dropoff_lat: LEAMINGTON.lat, dropoff_lng: LEAMINGTON.lng,
        pickup_time: null, created_at: isoOffset(-3 * 24 * 3600e3 + 240e3), picked_up_at: null, dropped_off_at: null, note: null },
      /* Dropped at the destination (Essex) */
      { id: 'b6', name: 'Sahil', phone: '15195550106', seats: 1,
        pickup_label: 'Tecumseh Road East, Windsor, Ontario, Canada', pickup_lat: 42.3055, pickup_lng: -82.9700,
        dropoff_label: 'Essex, Ontario, Canada', dropoff_lat: DEST.lat, dropoff_lng: DEST.lng,
        pickup_time: null, created_at: isoOffset(-3 * 24 * 3600e3 + 300e3), picked_up_at: null, dropped_off_at: null, note: null }
    ];

    if (stateKey === 'active') {
      bookings[3].picked_up_at = isoOffset(-15 * 60e3); /* Jordan already on board */
    } else if (stateKey === 'completed') {
      bookings.forEach(function (b) { b.picked_up_at = isoOffset(-40 * 60e3); b.dropped_off_at = isoOffset(-10 * 60e3); });
    }

    if (empty) bookings = [];

    return {
      trip: {
        id: tripId || 'trip-mock', status: tripStatus, driver_name: 'Test Driver',
        origin_label: (reverse ? DEST : ORIGIN).label, origin_lat: (reverse ? DEST : ORIGIN).lat, origin_lng: (reverse ? DEST : ORIGIN).lng,
        dest_label: (reverse ? ORIGIN : DEST).label, dest_lat: (reverse ? ORIGIN : DEST).lat, dest_lng: (reverse ? ORIGIN : DEST).lng,
        depart_at: departAt || '2026-09-24T18:30:00', seats_total: 6, price_per_seat: 10,
        join_url: 'https://pathfynder.ca/j/DEMO42'
      },
      bookings: bookings
    };
  }

  var STORE = {};
  var POSTED = []; /* defs of trips added by post() */
  var postSeq = 0;
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
      { id: 'trip-p2b', off: 2, key: 'draft', hh: 21, mm: 0, reverse: true, empty: true } /* second trip same day, Essex -> Windsor, no bookings (editable) */
    ];
    var raw = rawState();
    if (raw === 'draft' || raw === 'active' || raw === 'completed') defs.push({ id: 'trip-today', off: 0, key: raw });
    defs.sort(function (a, b) { return (a.off - b.off) || ((a.hh == null ? 18 : a.hh) - (b.hh == null ? 18 : b.hh)); });
    return defs.concat(POSTED); /* trips created through post() (already in STORE) */
  }
  function findDef(id) {
    var defs = tripDefs();
    for (var i = 0; i < defs.length; i++) if (defs[i].id === id) return defs[i];
    return null;
  }
  function getStore(id) {
    var def = findDef(id);
    if (!def) return null;
    if (!(id in STORE)) STORE[id] = buildPayload(def.key, id, dayAt(def.off, def.hh, def.mm), def.reverse, def.empty);
    return STORE[id];
  }

  /* Driver profile (mock of driver_profile_get). whatsapp_masked comes pre-masked; never a raw number. */
  var PROFILE = {
    name: 'Test Driver', photo_url: null, whatsapp_masked: '+1 \u2022\u2022\u2022 \u2022\u2022\u2022 4821', notifications_enabled: false,
    stats: { trips_completed: 42, member_since: '2026-09-01', passengers_drove: 118, total_earned: 1840 }
  };

  global.PF_MANAGE_MOCK = {
    list: function () {
      return new Promise(function (resolve) {
        setTimeout(function () {
          if (rawState() === 'invalid') { resolve({ error: 'invalid_token' }); return; }
          resolve({ trips: tripDefs().map(function (d) {
            var st = STORE[d.id];
            return { id: d.id, depart_at: st ? st.trip.depart_at : dayAt(d.off, d.hh, d.mm), status: st ? st.trip.status : d.key,
              origin_label: st ? st.trip.origin_label : (d.reverse ? DEST : ORIGIN).label, dest_label: st ? st.trip.dest_label : (d.reverse ? ORIGIN : DEST).label };
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
    profile: function () {
      return new Promise(function (resolve, reject) {
        setTimeout(function () {
          if (rawState() === 'invalid') { resolve({ error: 'invalid_token' }); return; }
          if (new URLSearchParams(location.search).get('pfail') === '1') { reject(new Error('mock profile failure')); return; }
          resolve(clone(PROFILE));
        }, 200);
      });
    },
    updateProfile: function (token, patch) {
      return new Promise(function (resolve, reject) {
        setTimeout(function () {
          if (shouldFail()) { reject(new Error('mock profile update failure')); return; }
          if (patch && patch.name != null) PROFILE.name = String(patch.name).trim();
          if (patch && patch.photo != null) PROFILE.photo_url = patch.photo;
          resolve({ name: PROFILE.name, photo_url: PROFILE.photo_url });
        }, 200);
      });
    },
    /* Mirrors trip_manage_update: f = { origin_label/lat/lng, dest_label/lat/lng, depart_at (ISO), seats, price } */
    update: function (token, tripId, f) {
      return new Promise(function (resolve, reject) {
        setTimeout(function () {
          if (shouldFail()) { reject(new Error('mock update failure')); return; }
          var st = getStore(tripId);
          if (!st) { resolve({ error: 'invalid_token' }); return; }
          if (st.bookings.length > 0) { resolve({ error: 'has_passengers' }); return; }
          if (st.trip.status !== 'draft') { resolve({ error: 'not_editable' }); return; }
          var bad = !(f.seats >= 1 && f.seats <= 8 && Math.floor(f.seats) === f.seats) || (f.price != null && f.price < 0) ||
            !f.origin_label || !f.dest_label ||
            [f.origin_lat, f.origin_lng, f.dest_lat, f.dest_lng].some(function (n) { return typeof n !== 'number' || !isFinite(n); }) ||
            Math.abs(f.origin_lat) > 90 || Math.abs(f.dest_lat) > 90 || Math.abs(f.origin_lng) > 180 || Math.abs(f.dest_lng) > 180 ||
            isNaN(new Date(f.depart_at).getTime());
          if (bad) { resolve({ error: 'invalid_input' }); return; }
          if (new Date(f.depart_at).getTime() < Date.now()) { resolve({ error: 'past_time' }); return; }
          var t = st.trip;
          t.origin_label = f.origin_label; t.origin_lat = f.origin_lat; t.origin_lng = f.origin_lng;
          t.dest_label = f.dest_label; t.dest_lat = f.dest_lat; t.dest_lng = f.dest_lng;
          t.depart_at = new Date(f.depart_at).toISOString(); t.seats_total = f.seats; t.price_per_seat = f.price == null ? null : f.price;
          resolve(clone(st));
        }, 300);
      });
    },
    /* Mirrors trip_post: f = { origin_*, dest_*, stops (array|null), seats, price, note, departures[ISO], returns[ISO] } -> { trip_ids } | { error } */
    post: function (token, f) {
      return new Promise(function (resolve, reject) {
        setTimeout(function () {
          if (shouldFail()) { reject(new Error('mock post failure')); return; }
          if (rawState() === 'invalid') { resolve({ error: 'invalid_token' }); return; }
          function num(n, lim) { return typeof n === 'number' && isFinite(n) && Math.abs(n) <= lim; }
          var deps = f.departures || [], rets = f.returns || [], stops = f.stops == null ? [] : f.stops;
          var dk = function (iso) { return new Date(iso).toDateString(); };
          var uniq = function (a) { return a.map(dk).filter(function (k, i, arr) { return arr.indexOf(k) === i; }).length === a.length; };
          var bad = !f.origin_label || !f.dest_label || !num(f.origin_lat, 90) || !num(f.dest_lat, 90) || !num(f.origin_lng, 180) || !num(f.dest_lng, 180) ||
            !(f.seats >= 1 && f.seats <= 8 && Math.floor(f.seats) === f.seats) || (f.price != null && f.price < 0) || (f.note != null && f.note.length > 300) ||
            !Array.isArray(stops) || stops.length > 5 ||
            stops.some(function (x) { return !x || !x.label || !num(x.lat, 90) || !num(x.lng, 180); }) ||
            deps.length < 1 || deps.length > 30 || rets.length > 30 || !uniq(deps) || !uniq(rets) ||
            deps.concat(rets).some(function (iso) { return isNaN(new Date(iso).getTime()); });
          if (bad) { resolve({ error: 'invalid_input' }); return; }
          if (deps.concat(rets).some(function (iso) { return new Date(iso).getTime() < Date.now(); })) { resolve({ error: 'past_time' }); return; }
          var ids = [];
          function add(iso, rev) {
            var id = 'trip-new-' + (++postSeq);
            var o = { label: f.origin_label, lat: f.origin_lat, lng: f.origin_lng }, d = { label: f.dest_label, lat: f.dest_lat, lng: f.dest_lng };
            var st = stops.length ? stops.slice() : null;
            if (rev) { var t = o; o = d; d = t; if (st) st.reverse(); }
            STORE[id] = { trip: { id: id, status: 'draft', driver_name: 'Test Driver',
              origin_label: o.label, origin_lat: o.lat, origin_lng: o.lng, dest_label: d.label, dest_lat: d.lat, dest_lng: d.lng,
              depart_at: new Date(iso).toISOString(), seats_total: f.seats, price_per_seat: f.price == null ? null : f.price,
              stops: st, note: f.note || null, join_url: null }, bookings: [] };
            POSTED.push({ id: id, off: 0, key: 'draft' });
            ids.push(id);
          }
          deps.forEach(function (iso) { add(iso, false); });
          rets.forEach(function (iso) { add(iso, true); });
          resolve({ trip_ids: ids });
        }, 300);
      });
    },
    /* Mirrors trip_post_recent: last distinct routes -> { trips: [...] } | { error } */
    recent: function (token) {
      return new Promise(function (resolve) {
        setTimeout(function () {
          if (rawState() === 'invalid') { resolve({ error: 'invalid_token' }); return; }
          resolve({ trips: [
            { origin_label: 'Windsor, Ontario, Canada', origin_lat: 42.3149, origin_lng: -83.0364, dest_label: 'Toronto, Ontario, Canada', dest_lat: 43.6532, dest_lng: -79.3832,
              stops: [{ label: 'Leamington, Ontario, Canada', lat: 42.0534, lng: -82.5999 }], seats: 3, price: 20, note: 'Pickup at the Tim Hortons' },
            { origin_label: 'London, Ontario, Canada', origin_lat: 42.9849, origin_lng: -81.2453, dest_label: 'Ottawa, Ontario, Canada', dest_lat: 45.4215, dest_lng: -75.6972,
              stops: [], seats: 4, price: 50, note: null },
            { origin_label: 'Windsor, Ontario, Canada', origin_lat: 42.3149, origin_lng: -83.0364, dest_label: 'London, Ontario, Canada', dest_lat: 42.9849, dest_lng: -81.2453,
              stops: [], seats: 2, price: null, note: null }
          ] });
        }, 200);
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
