// Baseline page: same tiles + same style as the future mbmap example.
// Reports (ms from navigation start unless noted):
//   importEnd   : maplibre-gl.mjs evaluated
//   load        : 'load' event
//   idle        : first 'idle' (all visible tiles loaded and drawn) = first full render
// then runs scripted pan / zoom animations and records rAF frame intervals
// and the CPU time of each Map#_render call.
const params = new URLSearchParams(location.search);
const marks = { scriptStart: performance.now() };
const maplibregl = await import("/bench/node_modules/maplibre-gl/dist/maplibre-gl.mjs");
marks.importEnd = performance.now();

const style = JSON.parse((await (await fetch("./style.json")).text()).replaceAll("{origin}", location.origin));
const longTasks = [];
try {
  new PerformanceObserver((list) => { for (const e of list.getEntries()) longTasks.push({ start: e.startTime, duration: e.duration }); })
    .observe({ type: "longtask", buffered: true });
} catch {}

const map = new maplibregl.Map({
  container: "map", style, center: [139.7671, 35.6812], zoom: 14.5,
  attributionControl: false, pixelRatio: Number(params.get("dpr") ?? devicePixelRatio),
});
// Register before anything can yield: idle may follow load in the same task.
const loaded = new Promise((r) => map.once("load", () => { marks.load = performance.now(); r(); }));
const idle = new Promise((r) => map.once("idle", () => { marks.idle = performance.now(); r(); }));
marks.mapConstructed = performance.now();
window.__map = map;

const gl = map.painter.context.gl;
const dbg = gl.getExtension("WEBGL_debug_renderer_info");
const renderer = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER);

const renderCpu = [];
const origRender = map._render.bind(map);
map._render = (ts) => { const t = performance.now(); const r = origRender(ts); renderCpu.push(performance.now() - t); return r; };


await loaded;
await idle;

async function scenario(name, start) {
  renderCpu.length = 0;
  const frames = [];
  let last = performance.now(), running = true;
  const tick = (t) => { frames.push(t - last); last = t; if (running) requestAnimationFrame(tick); };
  requestAnimationFrame((t) => { last = t; requestAnimationFrame(tick); });
  const ltBefore = longTasks.length;
  await new Promise((r) => { map.once("moveend", r); start(); });
  running = false;
  await new Promise((r) => map.once("idle", r));
  const s = [...frames].sort((a, b) => a - b), q = (p) => s[Math.min(s.length - 1, Math.floor(p * s.length))];
  const c = [...renderCpu].sort((a, b) => a - b), qc = (p) => c[Math.min(c.length - 1, Math.floor(p * c.length))];
  return {
    name, frames: frames.length,
    frameMs: { mean: frames.reduce((a, b) => a + b, 0) / frames.length, p50: q(0.5), p95: q(0.95), p99: q(0.99), max: s[s.length - 1] },
    over20ms: frames.filter((f) => f > 20).length,
    renderCpuMs: { p50: qc(0.5), p95: qc(0.95), max: c[c.length - 1] },
    longTasks: longTasks.slice(ltBefore),
  };
}

const D = 3000, linear = (t) => t;
const scenarios = [];
scenarios.push(await scenario("pan", () => map.panBy([900, 500], { duration: D, easing: linear })));
scenarios.push(await scenario("pan-back", () => map.panBy([-900, -500], { duration: D, easing: linear })));
scenarios.push(await scenario("zoom-in", () => map.easeTo({ zoom: 16.5, duration: D, easing: linear })));
scenarios.push(await scenario("zoom-out", () => map.easeTo({ zoom: 14, duration: D, easing: linear })));

window.__result = { marks, renderer, dpr: map.getPixelRatio(), userAgent: navigator.userAgent, version: maplibregl.getVersion?.() ?? maplibregl.version, scenarios };
