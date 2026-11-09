// Map.pickPosition, Map.castRay and Map.setViewshed (mbmap's 3D picking, line of sight and viewshed, drawn
// through the shadow map) in Chromium vs the analytic answers on boxes of known size (page/boxes.mjs):
// segments' first hits, picked points on a surface, and pixels tinted seen or hidden.
// Usage: node sight/golden.mjs (after npm --prefix npm run build); writes bench/results/sight-golden.json.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";
import { BOXES, CENTER, MODEL } from "./page/boxes.mjs";

const SEGMENTS = 400;
const PICKS = 24;
/** Meters a hit may lie from the analytic one: the ray's 2 cm width and its depth's 24 bits. */
const TOLERANCE = 0.05;

// Mercator x, y and the engine's heights (meters at the center's scale, as mbmap draws extrusions).
const mx = (lng) => (lng + 180) / 360;
const my = (lat) => (1 - Math.log(Math.tan(Math.PI / 4 + (lat * Math.PI) / 360)) / Math.PI) / 2;
const cosc = Math.cos((CENTER[1] * Math.PI) / 180);
/** Meters per mercator unit at the center (mbmap's pixels per meter: 6371008.8 m Earth). */
const METERS = 2 * Math.PI * 6371008.8 * cosc;
// The model box: 20 m either side on the 6378137 m sphere of Web Mercator, 40 m up in its own meters.
const modelHalf = 20 / (2 * Math.PI * 6378137 * Math.cos((MODEL[1] * Math.PI) / 180));
const modelTop = (40 * 6371008.8 * cosc) / (6378137 * Math.cos((MODEL[1] * Math.PI) / 180));
const boxes = [
  ...BOXES.map(([w, s, e, n, h]) => ({ x0: mx(w), x1: mx(e), y0: my(n), y1: my(s), h })),
  { x0: mx(MODEL[0]) - modelHalf, x1: mx(MODEL[0]) + modelHalf, y0: my(MODEL[1]) - modelHalf, y1: my(MODEL[1]) + modelHalf, h: modelTop },
];
const toLocal = ([lng, lat, h]) => [mx(lng), my(lat), h];
const toPlace = ([x, y, h]) => [x * 360 - 180, (360 / Math.PI) * Math.atan(Math.exp(Math.PI * (1 - 2 * y))) - 90, h];
/** Meters between two [lng, lat, h] near the center. */
const apart = (a, b) => {
  const [p, q] = [toLocal(a), toLocal(b)];
  return Math.hypot((p[0] - q[0]) * METERS, (p[1] - q[1]) * METERS, p[2] - q[2]);
};

/** The first t in [0, 1] where the segment a→b (local) enters a box or the ground, or null (slab test). */
function firstHit(a, b) {
  const d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]];
  let best = d[2] < 0 && a[2] >= 0 ? -a[2] / d[2] : Infinity;
  for (const box of boxes) {
    let t0 = 0;
    let t1 = 1;
    for (const [k, lo, hi] of [[0, box.x0, box.x1], [1, box.y0, box.y1], [2, 0, box.h]]) {
      if (d[k] === 0) {
        if (a[k] < lo || a[k] > hi) t0 = Infinity;
        continue;
      }
      const [u, v] = [(lo - a[k]) / d[k], (hi - a[k]) / d[k]];
      t0 = Math.max(t0, Math.min(u, v));
      t1 = Math.min(t1, Math.max(u, v));
    }
    if (t0 <= t1) best = Math.min(best, t0);
  }
  return best <= 1 ? best : null;
}

/** Meters from `p` (local) to the nearest surface: a box's face or the ground. */
function surfaceDistance(p) {
  let best = Math.abs(p[2]);
  for (const b of boxes) {
    const outX = Math.max(b.x0 - p[0], 0, p[0] - b.x1) * METERS;
    const outY = Math.max(b.y0 - p[1], 0, p[1] - b.y1) * METERS;
    const outZ = Math.max(-p[2], 0, p[2] - b.h);
    const inside = outX === 0 && outY === 0 && outZ === 0;
    const d = inside ? Math.min((p[0] - b.x0) * METERS, (b.x1 - p[0]) * METERS, (p[1] - b.y0) * METERS, (b.y1 - p[1]) * METERS, p[2], b.h - p[2]) : Math.hypot(outX, outY, outZ);
    best = Math.min(best, d);
  }
  return best;
}

let seed = 42;
const random = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const between = (a, b) => a + (b - a) * random();

const { server, origin } = await serve();
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
await page.goto(`${origin}/bench/sight/page/index.html`);
await page.waitForFunction(() => window.__loaded, null, { timeout: 60000 });
await page.evaluate(() => window.__settled());

// Segments: random ends around the boxes, from above the ground (extrusions have no floor) to above or below it.
const segments = Array.from({ length: SEGMENTS }, () => {
  const end = (low) => [between(139.7655, 139.7688), between(35.6796, 35.6819), between(low, 70)];
  return [end(0.5), end(-5)];
});
const cast = await page.evaluate((s) => s.map(([a, b]) => window.__map.castRay(a, b, 0)), segments);
const rays = { count: SEGMENTS, hits: 0, differ: 0, worst: 0, examples: [] };
segments.forEach(([a, b], i) => {
  const t = firstHit(toLocal(a), toLocal(b));
  const want = t === null ? null : toPlace(toLocal(a).map((v, k) => v + (toLocal(b)[k] - v) * t));
  const got = cast[i];
  // A hit within the tolerance of either end is ambiguous.
  if (want && (apart(want, b) < TOLERANCE || apart(want, a) < TOLERANCE)) return;
  if (want) rays.hits++;
  const error = want && got ? apart(want, got) : want || got ? Infinity : 0;
  rays.worst = Math.max(rays.worst, error === Infinity ? 0 : error);
  if (error > TOLERANCE) {
    rays.differ++;
    if (rays.examples.length < 5) rays.examples.push({ a, b, want, got });
  }
});

// Picks: screen points over the view, each on a surface.
const picks = { count: 0, differ: 0, worst: 0, examples: [] };
const points = [];
for (let y = 0; y < 4; y++) for (let x = 0; x < PICKS / 4; x++) points.push({ x: 60 + x * 130, y: 120 + y * 130 });
const picked = await page.evaluate((ps) => ps.map((p) => window.__map.pickPosition(p)), points);
picked.forEach((p, i) => {
  if (!p) return;
  picks.count++;
  const d = surfaceDistance(toLocal(p));
  picks.worst = Math.max(picks.worst, d);
  if (d > TOLERANCE) {
    picks.differ++;
    if (picks.examples.length < 5) picks.examples.push({ point: points[i], picked: p, distance: d });
  }
});

// Viewshed: ground points tinted seen (green) or hidden (red) as the segment from the observer says.
const VIEW = { position: [139.7656, 35.6807, 20], heading: 90, pitch: -5, horizontalFov: 100, verticalFov: 60, distance: 400 };
await page.evaluate(async (v) => {
  window.__map.setViewshed(v);
  await window.__settled();
}, VIEW);
const eye = toLocal(VIEW.position);
const tan = (deg) => Math.tan((deg * Math.PI) / 360);
/** Whether ground point `p` is within the view's frustum, by a margin (radians of tangent). */
function inView(p, margin) {
  const q = toLocal(p);
  const e = (q[0] - eye[0]) * METERS;
  const n = -(q[1] - eye[1]) * METERS;
  const u = q[2] - eye[2];
  const [h, k] = [(VIEW.heading * Math.PI) / 180, (VIEW.pitch * Math.PI) / 180];
  const f = [Math.sin(h) * Math.cos(k), Math.cos(h) * Math.cos(k), Math.sin(k)];
  const r = [Math.cos(h), -Math.sin(h), 0];
  const up = [r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0]];
  const z = e * f[0] + n * f[1] + u * f[2];
  const x = e * r[0] + n * r[1];
  const y = e * up[0] + n * up[1] + u * up[2];
  return z > 1 && z < VIEW.distance * (1 - margin) && Math.abs(x / z) < tan(VIEW.horizontalFov) - margin && Math.abs(y / z) < tan(VIEW.verticalFov) - margin;
}
const seen = (p) => firstHit(eye, toLocal([p[0], p[1], 0.05])) === null;
const ground = [];
for (let i = 0; i < 160; i++) ground.push([between(139.7652, 139.7695), between(35.6792, 35.6822), 0]);
// Where each lies on screen, and what is drawn there (a box in front of it is not the ground).
const screen = await page.evaluate((ps) => ps.map((p) => {
  const at = window.__map.project([p[0], p[1]]);
  return { ...at, drawn: window.__map.pickPosition(at) };
}), ground);
const shot = await page.screenshot();
const { decodePng } = await import("../lib/png.mjs");
const { width, rgba } = decodePng(shot);
const viewshed = { count: 0, differ: 0, examples: [] };
const step = 1.5 / METERS;
ground.forEach((p, i) => {
  const { x, y, drawn } = screen[i];
  if (!(x >= 2 && y >= 2 && x < 798 && y < 598) || !drawn || apart(drawn, p) > 0.5) return;
  const at = (Math.round(y) * width + Math.round(x)) * 4;
  const c = [rgba[at], rgba[at + 1], rgba[at + 2]];
  const shown = c[1] > c[0] + 30 ? "seen" : c[0] > c[1] + 30 ? "hidden" : c.every((v) => v > 250) ? "out" : null;
  // Too near an edge of the view or of a shadow to call.
  if (!shown) return;
  const near = [[0, 0], [step, 0], [-step, 0], [0, step], [0, -step]].map(([dx, dy]) => toPlace([mx(p[0]) + dx, my(p[1]) + dy, 0]));
  const inside = near.map((q) => inView(q, 0));
  if (inside.some((v) => v !== inside[0]) || inView(p, 0.02) !== inside[0]) return;
  const visible = near.map(seen);
  if (visible.some((v) => v !== visible[0])) return;
  const want = !inside[0] ? "out" : visible[0] ? "seen" : "hidden";
  viewshed.count++;
  if (want !== shown) {
    viewshed.differ++;
    if (viewshed.examples.length < 5) viewshed.examples.push({ point: p, want, shown, color: c });
  }
});
await browser.close();
server.close();

const results = { rays, picks, viewshed, errors };
await mkdir(path.join(ROOT, "bench/results"), { recursive: true });
await writeFile(path.join(ROOT, "bench/results/sight-golden.json"), JSON.stringify({ date: new Date().toISOString(), ...results }, null, 2) + "\n");
console.log(`rays: ${rays.count} segments, ${rays.hits} hitting, ${rays.differ} differ (worst ${rays.worst.toFixed(4)} m)`);
console.log(`picks: ${picks.count} points, ${picks.differ} off a surface (worst ${picks.worst.toFixed(4)} m)`);
console.log(`viewshed: ${viewshed.count} ground points, ${viewshed.differ} differ`);
for (const e of [...rays.examples, ...picks.examples, ...viewshed.examples]) console.log(JSON.stringify(e));
if (errors.length) console.log(errors);
if (rays.differ || picks.differ || viewshed.differ || errors.length || !viewshed.count || !rays.hits) process.exitCode = 1;
