// One style, tiles and camera script for mbmap and MapLibre (?engine=): time to
// first `idle`, then per scripted move the rAF intervals and per-frame CPU time
// of all rAF callbacks (both engines render inside rAF).
const params = new URLSearchParams(location.search);
const engine = params.get("engine");
const dpr = Number(params.get("dpr") ?? devicePixelRatio);

// CPU time of all rAF callbacks, summed per frame (callbacks of one frame share `t`).
const frameCpu = new Map();
const raf = requestAnimationFrame.bind(window);
window.requestAnimationFrame = (f) => raf((t) => {
  const t0 = performance.now();
  f(t);
  frameCpu.set(t, (frameCpu.get(t) ?? 0) + performance.now() - t0);
});

const START = { lng: 139.7671, lat: 35.6812, zoom: 14.5 };
const marks = { scriptStart: performance.now() };
const styleText = (await (await fetch("/bench/maplibre/style.json")).text()).replaceAll("{origin}", location.origin);

async function createMbmap() {
  // The minified build run.mjs produces, as an app bundler would ship it.
  const mbmap = await import("/bench/dist/mbmap-main.min.js");
  marks.imported = performance.now();
  const canvas = document.createElement("canvas");
  canvas.id = "map";
  document.body.append(canvas);
  const map = mbmap.create_map(canvas, styleText, START.lng, START.lat, START.zoom, 0, 0,
    "/worker/js/worker.mjs", "/_build/wasm-gc/release/build/worker/worker.wasm", 0);
  let idle = null;
  mbmap.map_on_idle(map, () => idle?.());
  return {
    nextIdle: () => new Promise((r) => { idle = r; }),
    set: (c) => mbmap.map_set_camera(map, c.lng, c.lat, c.zoom, 0, 0),
    get: () => mbmap.map_camera(map),
  };
}

async function createMaplibre() {
  const maplibregl = await import("/bench/node_modules/maplibre-gl/dist/maplibre-gl.mjs");
  marks.imported = performance.now();
  const div = document.createElement("div");
  div.id = "map";
  document.body.append(div);
  const style = JSON.parse(styleText);
  for (const s of Object.values(style.sources)) s.tiles = s.tiles.map((t) => new URL(t, location.href).href);
  const map = new maplibregl.Map({ container: div, style, center: [START.lng, START.lat], zoom: START.zoom, attributionControl: false, pixelRatio: dpr, fadeDuration: 0 });
  return {
    nextIdle: () => new Promise((r) => map.once("idle", r)),
    set: (c) => map.jumpTo({ center: [c.lng, c.lat], zoom: c.zoom }),
    get: () => ({ lng: map.getCenter().lng, lat: map.getCenter().lat, zoom: map.getZoom() }),
  };
}

const view = engine === "maplibre" ? await createMaplibre() : await createMbmap();
marks.created = performance.now();
await view.nextIdle();
marks.idle = performance.now();

const quantile = (xs, p) => { const s = [...xs].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(p * s.length))]; };

async function scenario(name, to, duration = 3000) {
  const from = view.get();
  frameCpu.clear();
  const intervals = [];
  await new Promise((done) => {
    const t0 = performance.now();
    let last = t0;
    const step = (t) => {
      const now = performance.now();
      intervals.push(now - last);
      last = now;
      const k = Math.min(1, (now - t0) / duration);
      view.set({ lng: from.lng + (to.lng - from.lng) * k, lat: from.lat + (to.lat - from.lat) * k, zoom: from.zoom + (to.zoom - from.zoom) * k });
      if (k < 1) requestAnimationFrame(step); else done();
    };
    requestAnimationFrame(step);
  });
  const cpu = [...frameCpu.values()];
  const settled = view.nextIdle();
  await Promise.race([settled, new Promise((r) => setTimeout(r, 5000))]);
  intervals.shift();
  return {
    name, frames: intervals.length,
    frameMs: { mean: intervals.reduce((a, b) => a + b, 0) / intervals.length, p95: quantile(intervals, 0.95), max: Math.max(...intervals) },
    over20ms: intervals.filter((f) => f > 20).length,
    rafCpuMs: { p50: quantile(cpu, 0.5), p95: quantile(cpu, 0.95), max: Math.max(...cpu) },
  };
}

// Pan by about (900, 500) CSS pixels at zoom 14.5, back, then zoom in and out.
const d = 900 / (512 * 2 ** 14.5) * 360, e = -500 / (512 * 2 ** 14.5) * 360 * Math.cos(START.lat * Math.PI / 180);
const scenarios = [];
scenarios.push(await scenario("pan", { ...START, lng: START.lng + d, lat: START.lat + e }));
scenarios.push(await scenario("pan-back", START));
scenarios.push(await scenario("zoom-in", { ...START, zoom: 16.5 }));
scenarios.push(await scenario("zoom-out", { ...START, zoom: 14 }));
window.__result = { engine, marks, dpr, userAgent: navigator.userAgent, scenarios };
