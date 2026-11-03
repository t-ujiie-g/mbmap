// A Geolocation for test pages (`page.addInitScript(fakeGeolocation)`): every
// watcher gets the positions and errors pushed through `window.__geo`.
export function fakeGeolocation() {
  const geo = {
    watchers: new Map(),
    next: 1,
    current: null,
    getCurrentPosition(ok, err) {
      setTimeout(() => (geo.current ? ok(geo.current) : err({ code: 2, message: "unavailable" })), 0);
    },
    watchPosition(ok, err) {
      const id = geo.next++;
      geo.watchers.set(id, { ok, err });
      if (geo.current) setTimeout(() => ok(geo.current), 0);
      return id;
    },
    clearWatch(id) {
      geo.watchers.delete(id);
    },
    push(lng, lat, accuracy) {
      geo.current = { coords: { longitude: lng, latitude: lat, accuracy, heading: null, altitude: null, altitudeAccuracy: null, speed: null }, timestamp: Date.now() };
      for (const w of [...geo.watchers.values()]) w.ok(geo.current);
    },
    fail(code) {
      for (const w of [...geo.watchers.values()]) w.err({ code, message: `failed ${code}` });
    },
  };
  window.__geo = geo;
  Object.defineProperty(navigator, "geolocation", { value: geo, configurable: true });
}
