// core's camera math (bench/entry/camera.mbt) vs MapLibre GL JS 6.16.0's Camera in Node with
// frozen time; fails beyond 1e-6 px, 1e-7°, 1e-8 zoom or 1e-5 ms.
// Usage: node lib/run-bundled.mjs bench/camera/golden.mjs; writes bench/results/camera-golden.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { Camera } from "maplibre-src/ui/camera.ts";
import { LngLatBounds } from "maplibre-src/geo/lng_lat_bounds.ts";
import { defaultEasing } from "maplibre-src/util/util.ts";
import { restoreNow, setNow } from "maplibre-src/util/time_control.ts";
import { nodeImportJs } from "../lib/node-io.mjs";
import { ENTRY_JS } from "../lib/entry.mjs";
import { ROOT } from "../lib/root.mjs";

const mbt = await nodeImportJs(ENTRY_JS);
// MapLibre asks the browser whether to skip animations.
globalThis.matchMedia = () => ({ matches: false });
const nums = (s) => (s === "" ? [] : s.split(",").map(Number));

const TOKYO = [139.7671, 35.6812];
const views = [];
for (const [w, h] of [[800, 600], [600, 900]]) {
  for (const [zoom, pitch, bearing] of [[14, 0, 0], [14, 45, 30], [12.5, 70, -120], [16, 80, 170], [3, 20, 10], [0.5, 0, 0], [0, 0, 0]]) {
    views.push({ w, h, center: TOKYO, zoom, pitch, bearing });
  }
}
views.push({ w: 800, h: 600, center: [179.5, 70], zoom: 4, pitch: 30, bearing: -45 });
views.push({ w: 800, h: 600, center: [10, -84], zoom: 2, pitch: 0, bearing: 0 });
views.push({ w: 800, h: 600, center: [150, 20], zoom: 9, pitch: 10, bearing: 0, bounds: [139, 35, 140, 36] });
views.push({ w: 800, h: 600, center: TOKYO, zoom: 3, pitch: 0, bearing: 0, bounds: [139, 35, 140, 36] });
views.push({ w: 800, h: 600, center: TOKYO, zoom: 9, pitch: 0, bearing: 0, minZoom: 10, maxZoom: 12, minPitch: 10, maxPitch: 40 });

function maplibre(v) {
  const frames = [];
  const cam = new Camera({
    requestRenderFrame: (f) => frames.push(f),
    cancelRenderFrame: () => {},
    minZoom: v.minZoom ?? 0,
    maxZoom: v.maxZoom ?? 22,
    minPitch: v.minPitch ?? 0,
    maxPitch: v.maxPitch ?? 85,
  });
  cam.transform.resize(v.w, v.h);
  if (v.bounds) cam.transform.setMaxBounds(new LngLatBounds([v.bounds[0], v.bounds[1]], [v.bounds[2], v.bounds[3]]));
  cam.jumpTo({ center: v.center, zoom: v.zoom, pitch: v.pitch, bearing: v.bearing });
  // Runs the frame MapLibre asked for at `t` ms.
  cam.frameAt = (t) => {
    setNow(t);
    const f = frames.splice(0);
    for (const g of f) g();
  };
  return cam;
}
const ours = (v) => [v.w, v.h, v.center[0], v.center[1], v.zoom, v.bearing, v.pitch, v.minZoom ?? 0, v.maxZoom ?? 22, v.minPitch ?? 0, v.maxPitch ?? 85, ...(v.bounds ?? [NaN, 0, 0, 0])];
const state = (tr) => [tr.center.lng, tr.center.lat, tr.zoom, tr.bearing, tr.pitch];

const rows = [];
const worst = { px: 0, deg: 0, zoom: 0, ms: 0 };
// Largest difference of camera tuples (lng, lat in degrees; zoom; bearing, pitch in degrees).
function cameraDiff(a, b) {
  let deg = 0;
  let zoom = 0;
  for (let i = 0; i < a.length; i += 5) {
    const dl = Math.abs(((a[i] - b[i] + 540) % 360) - 180);
    const db = Math.abs(((a[i + 3] - b[i + 3] + 540) % 360) - 180);
    deg = Math.max(deg, dl, Math.abs(a[i + 1] - b[i + 1]), db, Math.abs(a[i + 4] - b[i + 4]));
    zoom = Math.max(zoom, Math.abs(a[i + 2] - b[i + 2]));
  }
  return { deg: a.length === b.length ? deg : Infinity, zoom: a.length === b.length ? zoom : Infinity };
}
function record(op, v, d) {
  rows.push({ op, view: `${v.w}x${v.h} z${v.zoom} p${v.pitch} b${v.bearing}${v.bounds ? " bounds" : ""}${v.minZoom !== undefined ? " limits" : ""}`, ...d });
  for (const k of Object.keys(d)) worst[k] = Math.max(worst[k], d[k]);
}

const KS = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1];
for (const v of views) {
  try {
    runView(v);
  } catch (e) {
    console.log("failed on", JSON.stringify(v), e.message, e.stack.split("\n").slice(1, 4).join(" | ").slice(0, 600));
    throw e;
  }
}
function runView(v) {
  const cam = maplibre(v);
  const tr = cam.transform;
  record("constrain", v, cameraDiff(state(tr), nums(mbt.camera_constrain(ours(v)))));

  const lnglats = [];
  for (const [dx, dy] of [[0, 0], [0.01, 0.01], [-0.05, 0.02], [0.2, -0.1], [1, 1]]) lnglats.push(tr.center.lng + dx * 10 ** (2 - v.zoom / 7), Math.max(-80, Math.min(80, tr.center.lat + dy * 10 ** (2 - v.zoom / 7))));
  const ref = [];
  for (let i = 0; i < lnglats.length; i += 2) {
    const p = tr.locationToScreenPoint({ lng: lnglats[i], lat: lnglats[i + 1] });
    ref.push(p.x, p.y);
  }
  const got = nums(mbt.camera_project(ours(v), lnglats));
  record("project", v, { px: Math.max(...ref.map((r, i) => Math.abs(r - got[i]))) });

  const top = Math.max(0, v.h / 2 - (v.h / 2 - tr.locationToScreenPoint(tr.center).y) - 0);
  const screen = [];
  for (const [fx, fy] of [[0.5, 0.5], [0, 1], [1, 1], [0.25, 0.8], [0.9, 0.6]]) screen.push(fx * v.w, Math.max(top, fy * v.h));
  const un = [];
  for (let i = 0; i < screen.length; i += 2) {
    const p = tr.screenPointToLocation({ x: screen[i], y: screen[i + 1] });
    un.push(p.lng, p.lat);
  }
  const ug = nums(mbt.camera_unproject(ours(v), screen));
  record("unproject", v, { deg: Math.max(...un.map((r, i) => Math.abs(r - ug[i]))) });

  const b = tr.getBounds();
  const bg = nums(mbt.camera_bounds(ours(v)));
  record("getBounds", v, { deg: Math.max(...[b.getWest(), b.getSouth(), b.getEast(), b.getNorth()].map((r, i) => Math.abs(r - bg[i]))) });

  for (const fit of [
    { bounds: [139.5, 35.5, 140, 35.8], bearing: 0, padding: [0, 0, 0, 0], offset: [0, 0] },
    { bounds: [139.5, 35.5, 140, 35.8], bearing: 30, padding: [20, 40, 10, 80], offset: [15, -25], maxZoom: 9 },
    { bounds: [170, -10, -170, 10], bearing: -60, padding: [5, 5, 5, 5], offset: [0, 0] },
  ]) {
    const [w, s, e, n] = fit.bounds;
    const r = cam.cameraForBounds([[w, s], [e, n]], { bearing: fit.bearing, padding: { top: fit.padding[0], right: fit.padding[1], bottom: fit.padding[2], left: fit.padding[3] }, offset: fit.offset, ...(fit.maxZoom === undefined ? {} : { maxZoom: fit.maxZoom }) });
    const g = nums(mbt.camera_fit(ours(v), [w, s, e, n, fit.bearing, ...fit.padding, ...fit.offset, fit.maxZoom ?? NaN]));
    const want = r ? [r.center.lng, r.center.lat, r.zoom, r.bearing] : [];
    const d = cameraDiff([...want, 0], g.length ? [g[0], g[1], g[2], g[3], 0] : []);
    record("cameraForBounds", v, r || g.length ? d : { deg: 0, zoom: 0 });
  }

  for (const target of [
    { center: [139.9, 35.5], zoom: v.zoom + 2, bearing: 90, pitch: 30 },
    { center: [140.5, 36.5], zoom: v.zoom - 3 },
    { zoom: v.zoom + 1.5, around: [tr.center.lng + 0.001, tr.center.lat - 0.001] },
    { center: [-170, 10], bearing: -170, offset: [30, -20] },
  ]) {
    const D = 1000;
    const m = maplibre(v);
    setNow(0);
    m.easeTo({ ...target, duration: D, easing: (t) => t });
    const ref2 = [];
    for (const k of KS) {
      m.frameAt(k * D);
      ref2.push(...state(m.transform));
    }
    const g = [NaN, NaN, NaN, NaN, NaN, NaN, NaN, 0, 0];
    if (target.center) [g[0], g[1]] = target.center;
    if (target.zoom !== undefined) g[2] = target.zoom;
    if (target.bearing !== undefined) g[3] = target.bearing;
    if (target.pitch !== undefined) g[4] = target.pitch;
    if (target.around) [g[5], g[6]] = target.around;
    if (target.offset) [g[7], g[8]] = target.offset;
    record("easeTo", v, cameraDiff(ref2, nums(mbt.camera_ease(ours(v), g, KS))));

    if (target.around) continue;
    const f = maplibre(v);
    setNow(0);
    f.flyTo({ ...target, easing: (t) => t });
    const duration = f._easeOptions?.duration ?? 0;
    const ref3 = [];
    for (const k of KS) {
      f.frameAt(k * duration);
      ref3.push(...state(f.transform));
    }
    const fg = nums(mbt.camera_fly(ours(v), g, [NaN, NaN, NaN, NaN], KS));
    if (fg.length === 0) {
      record("flyTo", v, duration === 0 ? { ms: 0 } : { ms: Infinity });
    } else {
      record("flyTo", v, { ms: Math.abs(fg[0] - duration), ...cameraDiff(ref3, fg.slice(1)) });
    }
  }
}
restoreNow();

const ts = Array.from({ length: 101 }, (_, i) => i / 100);
const eg = nums(mbt.camera_easing(ts));
rows.push({ op: "defaultEasing", view: "-", deg: Math.max(...ts.map((t, i) => Math.abs(defaultEasing(t) - eg[i]))) });
worst.deg = Math.max(worst.deg, rows.at(-1).deg);

console.log(`camera golden: ${views.length} views, ${rows.length} comparisons; largest difference ${worst.px.toExponential(2)} px, ${worst.deg.toExponential(2)}°, ${worst.zoom.toExponential(2)} zoom, ${worst.ms.toExponential(2)} ms`);
await writeFile(path.join(ROOT, "bench/results/camera-golden.json"), JSON.stringify({ reference: "maplibre-gl 6.16.0", worst, rows }, null, 2) + "\n");
const bad = rows.filter((r) => !((r.px ?? 0) <= 1e-6 && (r.deg ?? 0) <= 1e-7 && (r.zoom ?? 0) <= 1e-8 && (r.ms ?? 0) <= 1e-5));
for (const r of bad.slice(0, 30)) console.log("beyond tolerance:", JSON.stringify(r));
if (bad.length) process.exitCode = 1;
