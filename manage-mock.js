/* ---------------------------------------------------------------------
   Local mock data for /manage (manage.html), matching the
   trip_manage_get / trip_manage_action RPC contract (see plan for
   /m/:token). Loaded only when ?mock=1. In-memory only, per query
   `state` param: draft | active (default) | completed | invalid.
   ?fail=1 makes trip_manage_action reject, to test optimistic rollback.
   TODO: delete this file once trip_manage_get / trip_manage_action ship.
   --------------------------------------------------------------------- */
(function (global) {
  var ORIGIN = { lat: 42.3149, lng: -83.0364, label: 'Windsor, ON' };
  var DEST = { lat: 42.1751, lng: -82.8185, label: 'Essex, ON' };
  var LEAMINGTON = { lat: 42.0531, lng: -82.5998 };

  function isoOffset(ms) { return new Date(Date.now() + ms).toISOString(); }
  function clone(o) { return o == null ? o : JSON.parse(JSON.stringify(o)); }

  function buildPayload(stateKey) {
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
        id: 'trip-mock', status: tripStatus, driver_name: 'Test Driver',
        origin_label: ORIGIN.label, origin_lat: ORIGIN.lat, origin_lng: ORIGIN.lng,
        dest_label: DEST.label, dest_lat: DEST.lat, dest_lng: DEST.lng,
        depart_at: '2026-09-24T18:30:00', seats_total: 4, price_per_seat: 10,
        join_url: 'https://pathfynder.ca/j/DEMO42'
      },
      bookings: bookings
    };
  }

  var STORE = {};
  function stateKey() {
    try { return new URLSearchParams(location.search).get('state') || 'active'; }
    catch (e) { return 'active'; }
  }
  function shouldFail() {
    try { return new URLSearchParams(location.search).get('fail') === '1'; }
    catch (e) { return false; }
  }
  function getStore() {
    var k = stateKey();
    if (!(k in STORE)) STORE[k] = buildPayload(k);
    return STORE[k];
  }

  global.PF_MANAGE_MOCK = {
    get: function () {
      return new Promise(function (resolve) {
        setTimeout(function () {
          var st = getStore();
          resolve(st ? clone(st) : { error: 'invalid_token' });
        }, 300);
      });
    },
    action: function (token, action, bookingId) {
      return new Promise(function (resolve, reject) {
        setTimeout(function () {
          if (shouldFail()) { reject(new Error('mock action failure')); return; }
          var st = getStore();
          if (!st) { resolve({ error: 'invalid_token' }); return; }
          var now = new Date().toISOString();
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
