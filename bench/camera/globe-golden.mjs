// globe's camera (bench/entry/globe.mbt) vs MapLibre 6.16.0's globe transform driven by its Camera in
// Node with frozen time, the transition taken from each frame's zoom; tolerances as camera:golden, and
// coveringTiles must give the same tiles in order. Writes bench/results/globe-golden.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import Point from "@mapbox/point-geometry";
import { Camera } from "maplibre-src/ui/camera.ts";
import { LngLatBounds } from "maplibre-src/geo/lng_lat_bounds.ts";
import { createProjectionFromName } from "maplibre-src/geo/projection/projection_factory.ts";
import { coveringTiles } from "maplibre-src/geo/projection/covering_tiles.ts";
import { EvaluationParameters } from "maplibre-src/style/evaluation_parameters.ts";
import { restoreNow, setNow } from "maplibre-src/util/time_control.ts";
import { nodeImportJs } from "../lib/node-io.mjs";
import { ENTRY_JS } from "../lib/entry.mjs";
import { ROOT } from "../lib/root.mjs";

const mbt = await nodeImportJs(ENTRY_JS);
globalThis.matchMedia = () => ({ matches: false });
const nums = (s) => (s === "" ? [] : s.split(",").map(Number));
const PROJECTIONS = { mercator: 0, globe: 1, "vertical-perspective": 2 };

const TOKYO = [139.7671, 35.6812];
const views = [];
for (const [w, h] of [[800, 600], [600, 900]]) {
  for (const [zoom, pitch, bearing] of [[2, 0, 0], [3.5, 40, 30], [6, 60, -120], [11.5, 30, 10], [14, 45, 30], [0.5, 0, 0], [1, 75, 170]]) {
    views.push({ w, h, center: TOKYO, zoom, pitch, bearing, projection: "globe" });
  }
}
views.push({ w: 800, h: 600, center: [179.5, 70], zoom: 3, pitch: 30, bearing: -45, projection: "globe" });
views.push({ w: 800, h: 600, center: [10, -84], zoom: 2, pitch: 0, bearing: 0, projection: "globe" });
views.push({ w: 800, h: 600, center: [-30, 88], zoom: 4, pitch: 20, bearing: 60, projection: "globe" });
views.push({ w: 800, h: 600, center: TOKYO, zoom: 9, pitch: 0, bearing: 0, minZoom: 10, maxZoom: 12, minPitch: 10, maxPitch: 40, projection: "globe" });
views.push({ w: 800, h: 600, center: TOKYO, zoom: 4, pitch: 0, bearing: 0, bounds: [139, 35, 140, 36], projection: "globe" });
for (const [zoom, pitch, bearing] of [[5, 70, 20], [6.5, 80, -60], [8, 60, 135], [7.2, 85, 0], [4.6, 50, -10]]) {
  views.push({ w: 800, h: 600, center: TOKYO, zoom, pitch, bearing, projection: "globe" });
}
views.push({ w: 1200, h: 500, center: [-100, 40], zoom: 5.5, pitch: 75, bearing: 100, projection: "globe" });
views.push({ w: 800, h: 600, center: [179.9, -20], zoom: 6, pitch: 65, bearing: -90, projection: "globe" });
views.push({ w: 800, h: 600, center: TOKYO, zoom: 13, pitch: 50, bearing: 20, projection: "vertical-perspective" });
views.push({ w: 800, h: 600, center: TOKYO, zoom: 3, pitch: 10, bearing: 0, projection: "mercator" });

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
  const { projection, transform, cameraHelper } = createProjectionFromName(v.projection, undefined, {});
  cam.migrateProjection(transform, cameraHelper);
  const tr = cam.transform;
  tr.resize(v.w, v.h);
  if (v.bounds) tr.setMaxBounds(new LngLatBounds([v.bounds[0], v.bounds[1]], [v.bounds[2], v.bounds[3]]));
  cam.jumpTo({ center: v.center, zoom: v.zoom, pitch: v.pitch, bearing: v.bearing });
  // The map evaluates the projection at the zoom of each frame it draws.
  cam.render = () => {
    projection?.recalculate?.(new EvaluationParameters(cam.transform.zoom));
    cam.transform.setTransitionState(projection?.transitionState ?? 0);
  };
  cam.render();
  cam.frameAt = (t) => {
    setNow(t);
    const f = frames.splice(0);
    for (const g of f) g();
    cam.render();
  };
  return cam;
}
const transitionOf = (tr) => tr._globeness ?? (tr.getClippingPlane() ? 1 : 0);
const ours = (v) => [v.w, v.h, v.center[0], v.center[1], v.zoom, v.bearing, v.pitch, v.minZoom ?? 0, v.maxZoom ?? 22, v.minPitch ?? 0, v.maxPitch ?? 85, ...(v.bounds ?? [NaN, 0, 0, 0]), PROJECTIONS[v.projection]];
const state = (tr) => [tr.center.lng, tr.center.lat, tr.zoom, tr.bearing, tr.pitch, transitionOf(tr)];

const rows = [];
const worst = { px: 0, deg: 0, zoom: 0, ms: 0, rel: 0, tiles: 0 };
// coveringTiles options: tile size, min zoom, max zoom, roundZoom.
const COVERING = [[512, undefined, undefined, false], [256, undefined, undefined, true], [512, undefined, 14, true], [256, 2, undefined, false], [512, 2, 6, false]];
// Largest difference of camera tuples (lng, lat, zoom, bearing, pitch, transition).
function cameraDiff(a, b, n = 6) {
  let deg = 0;
  let zoom = 0;
  for (let i = 0; i < a.length; i += n) {
    const dl = Math.abs(((a[i] - b[i] + 540) % 360) - 180);
    const db = Math.abs(((a[i + 3] - b[i + 3] + 540) % 360) - 180);
    deg = Math.max(deg, dl, Math.abs(a[i + 1] - b[i + 1]), db, Math.abs(a[i + 4] - b[i + 4]));
    zoom = Math.max(zoom, Math.abs(a[i + 2] - b[i + 2]), n === 6 ? Math.abs(a[i + 5] - b[i + 5]) : 0);
  }
  return { deg: a.length === b.length ? deg : Infinity, zoom: a.length === b.length ? zoom : Infinity };
}
function record(op, v, d) {
  rows.push({ op, view: `${v.projection} ${v.w}x${v.h} ${v.center} z${v.zoom} p${v.pitch} b${v.bearing}${v.bounds ? " bounds" : ""}${v.minZoom !== undefined ? " limits" : ""}`, ...d });
  for (const k of Object.keys(d)) worst[k] = Math.max(worst[k], d[k]);
}
const maxAbs = (a, b) => (a.length === b.length ? Math.max(0, ...a.map((r, i) => Math.abs(r - b[i]))) : Infinity);

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
  record("constrain", v, cameraDiff(state(tr), nums(mbt.globe_state(ours(v)))));

  const lnglats = [];
  for (const [dx, dy] of [[0, 0], [0.01, 0.01], [-0.05, 0.02], [0.2, -0.1], [1, 1], [30, 10], [100, -20], [-170, 40]]) {
    lnglats.push(tr.center.lng + dx * (Math.abs(dx) >= 30 ? 1 : 10 ** (2 - v.zoom / 7)), Math.max(-80, Math.min(80, tr.center.lat + dy * (Math.abs(dx) >= 30 ? 1 : 10 ** (2 - v.zoom / 7)))));
  }
  const ref = [];
  for (let i = 0; i < lnglats.length; i += 2) {
    const ll = { lng: lnglats[i], lat: lnglats[i + 1] };
    const occluded = transitionOf(tr) > 0 && tr.isLocationOccluded(ll);
    const p = tr.locationToScreenPoint(ll);
    ref.push(p.x, p.y, occluded ? 1 : 0);
  }
  const got = nums(mbt.globe_project(ours(v), lnglats));
  // Mercator points behind the camera are left out (core's own golden compares those).
  const keep = (i) => transitionOf(tr) > 0 || Number.isFinite(ref[i - (i % 3)]);
  const pd = ref.map((r, i) => (keep(i) ? Math.abs(r - got[i]) : 0));
  record("project and occlusion", v, { px: Math.max(...pd) });

  const screen = [];
  for (const [fx, fy] of [[0.5, 0.5], [0, 1], [1, 1], [0.25, 0.8], [0.9, 0.6], [0, 0], [0.5, 0], [1, 0.3]]) screen.push(fx * v.w, fy * v.h);
  const un = [];
  const unOk = [];
  for (let i = 0; i < screen.length; i += 2) {
    const pt = new Point(screen[i], screen[i + 1]);
    const p = tr.screenPointToLocation(pt);
    unOk.push(transitionOf(tr) > 0 || tr.isPointOnMapSurface(pt));
    un.push(p?.lng ?? NaN, p?.lat ?? NaN);
  }
  const ug = nums(mbt.globe_unproject(ours(v), screen));
  record("unproject", v, { deg: Math.max(...un.map((r, i) => (unOk[i >> 1] ? Math.abs(((r - ug[i] + 540) % 360) - 180) : 0))) });

  if (transitionOf(tr) > 0) {
    const m = nums(mbt.globe_matrices(ours(v)));
    const screenOf = (mat, [x, y, z]) => {
      const c = [0, 1, 2, 3].map((r) => mat[r] * x + mat[4 + r] * y + mat[8 + r] * z + mat[12 + r]);
      return [((c[0] / c[3] + 1) / 2) * v.w, ((1 - c[1] / c[3]) / 2) * v.h];
    };
    let px = 0;
    for (const p of [[0, 0, 1], [0.3, 0.5, 0.81], [-0.7, 0.1, 0.7], [0.58, 0.58, 0.58]]) {
      const [a, b] = [screenOf(tr.modelViewProjectionMatrix, p), screenOf(m, p)];
      px = Math.max(px, Math.abs(a[0] - b[0]), Math.abs(a[1] - b[1]));
    }
    const proj = Math.max(...[...tr.projectionMatrix].map((r, i) => Math.abs(r - m[16 + i]) / Math.max(1, Math.abs(r))));
    const planes = Math.max(Math.abs(tr.nearZ - m[32]) / tr.nearZ, Math.abs(tr.farZ - m[33]) / tr.farZ);
    const camPos = maxAbs([...tr.cameraPosition], m.slice(34, 37));
    const clip = maxAbs([...tr.getClippingPlane()], m.slice(37, 41));
    const altitude = Math.abs(tr.getCameraAltitude() - m[41]) / tr.getCameraAltitude();
    record("globe matrices", v, { px, rel: Math.max(proj, planes, camPos, clip, altitude) });

    for (const [tileSize, minzoom, maxzoom, roundZoom] of COVERING) {
      const want = coveringTiles(tr, { tileSize, minzoom, maxzoom, roundZoom }).flatMap((t) => [t.canonical.z, t.canonical.x, t.canonical.y]);
      const got = nums(mbt.globe_covering(ours(v), [tileSize, minzoom ?? 0, maxzoom ?? NaN, roundZoom ? 1 : 0]));
      let tiles = Math.abs(want.length - got.length) / 3;
      for (let i = 0; i < Math.min(want.length, got.length); i += 3) {
        if (want[i] !== got[i] || want[i + 1] !== got[i + 1] || want[i + 2] !== got[i + 2]) tiles++;
      }
      record(`coveringTiles ${tileSize} ${minzoom ?? 0}-${maxzoom ?? ""}${roundZoom ? " round" : ""} (${want.length / 3})`, v, { tiles });
    }
  }

  const b = tr.getBounds();
  record("getBounds", v, { deg: maxAbs([b.getWest(), b.getSouth(), b.getEast(), b.getNorth()], nums(mbt.globe_bounds(ours(v)))) });

  for (const fit of [
    { bounds: [139.5, 35.5, 140, 35.8], bearing: 0, padding: [0, 0, 0, 0], offset: [0, 0] },
    { bounds: [139.5, 35.5, 140, 35.8], bearing: 30, padding: [20, 40, 10, 80], offset: [15, -25], maxZoom: 9 },
    { bounds: [170, -10, -170, 10], bearing: -60, padding: [5, 5, 5, 5], offset: [0, 0] },
    { bounds: [100, -40, 160, 50], bearing: 0, padding: [10, 10, 10, 10], offset: [0, 0] },
  ]) {
    const [w, s, e, n] = fit.bounds;
    const r = cam.cameraForBounds([[w, s], [e, n]], { bearing: fit.bearing, padding: { top: fit.padding[0], right: fit.padding[1], bottom: fit.padding[2], left: fit.padding[3] }, offset: fit.offset, ...(fit.maxZoom === undefined ? {} : { maxZoom: fit.maxZoom }) });
    const g = nums(mbt.globe_fit(ours(v), [w, s, e, n, fit.bearing, ...fit.padding, ...fit.offset, fit.maxZoom ?? NaN]));
    const want = r ? [r.center.lng, r.center.lat, r.zoom, r.bearing] : [];
    const d = cameraDiff([...want, 0], g.length ? [g[0], g[1], g[2], g[3], 0] : [], 5);
    record("cameraForBounds", v, r || g.length ? d : { deg: 0, zoom: 0 });
  }

  for (const target of [
    { center: [139.9, 35.5], zoom: v.zoom + 2, bearing: 90, pitch: 30 },
    { center: [140.5, 36.5], zoom: v.zoom - 3 },
    { zoom: v.zoom + 1.5, around: [tr.center.lng + 0.001, tr.center.lat - 0.001] },
    { center: [-170, 10], bearing: -170, offset: [30, -20] },
    { center: [-74, 40.7], zoom: 12.5 },
    { center: [2.35, 48.85], zoom: 4, pitch: 0 },
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
    record("easeTo", v, cameraDiff(ref2, nums(mbt.globe_ease(ours(v), g, KS))));

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
    const fg = nums(mbt.globe_fly(ours(v), g, [NaN, NaN, NaN, NaN], KS));
    if (fg.length === 0) {
      record("flyTo", v, duration === 0 ? { ms: 0 } : { ms: Infinity });
    } else {
      record("flyTo", v, { ms: Math.abs(fg[0] - duration), ...cameraDiff(ref3, fg.slice(1)) });
    }
  }

  // Gesture frames as the handler manager applies them (no terrain).
  const ops = [
    [v.w * 0.6, v.h * 0.55, 12, -8, 0, 0, 0],
    [v.w * 0.6, v.h * 0.55, 30, 15, 0, 0, 0],
    [v.w * 0.3, v.h * 0.7, 0, 0, 0.4, 0, 0],
    [v.w * 0.8, v.h * 0.2, 0, 0, -0.7, 0, 0],
    [v.w / 2, v.h / 2, 0, 0, 0, 12, 5],
    [v.w * 0.2, v.h * 0.4, -40, 25, 0.2, 0, 0],
    [v.w * 0.95, v.h * 0.05, 5, 5, 0.1, 0, 0],
  ];
  const gm = maplibre(v);
  const ref4 = [];
  for (const [x, y, px, py, zd, bd, pd2] of ops) {
    const t = gm.transform;
    const helper = gm.cameraHelper;
    const around = new Point(x, y);
    const panDelta = px || py ? new Point(px, py) : undefined;
    const deltas = { panDelta, zoomDelta: zd, rollDelta: 0, pitchDelta: pd2, bearingDelta: bd, around, aroundElevation: undefined };
    let a = around;
    if (helper.useGlobeControls && !t.isPointOnMapSurface(a)) a = t.centerPoint;
    const pre = a.distSqr(t.centerPoint) < 1e-2 ? t.center : t.screenPointToLocation(panDelta ? a.sub(panDelta) : a);
    helper.handleMapControlsRollPitchBearingZoom(deltas, t);
    if (!helper.useGlobeControls && !t.isPointOnMapSurface(deltas.around)) {
      if (panDelta) t.setCenter(t.screenPointToLocation(t.centerPoint.sub(panDelta)));
    } else {
      helper.handleMapControlsPan(deltas, t, pre);
    }
    gm.render();
    ref4.push(...state(t));
  }
  record("gestures", v, cameraDiff(ref4, nums(mbt.globe_controls(ours(v), ops.flat()))));

  const am = maplibre(v);
  const pts = [[tr.center.lng + 1, tr.center.lat + 0.5, v.w * 0.3, v.h * 0.4], [tr.center.lng - 0.2, tr.center.lat, v.w * 0.7, v.h * 0.8]];
  const ref5 = [];
  for (const [lng, lat, x, y] of pts) {
    am.transform.setLocationAtPoint({ lng, lat }, new Point(x, y));
    ref5.push(...state(am.transform));
  }
  record("setLocationAtPoint", v, cameraDiff(ref5, nums(mbt.globe_at_point(ours(v), pts.flat()))));

  for (const pan of [[40, -10], [-300, 120]]) {
    const r = maplibre(v).cameraHelper.handlePanInertia(new Point(pan[0], pan[1]), tr);
    const gi = nums(mbt.globe_inertia(ours(v), pan));
    record("pan inertia", v, { deg: maxAbs([r.easingCenter.lng, r.easingCenter.lat], gi.slice(0, 2)), px: maxAbs([r.easingOffset.x, r.easingOffset.y], gi.slice(2)) });
  }
}
restoreNow();

console.log(`globe golden: ${views.length} views, ${rows.length} comparisons; largest difference ${worst.px.toExponential(2)} px, ${worst.deg.toExponential(2)}°, ${worst.zoom.toExponential(2)} zoom, ${worst.ms.toExponential(2)} ms, ${worst.rel.toExponential(2)} relative, ${worst.tiles} covering tiles differ`);
await writeFile(path.join(ROOT, "bench/results/globe-golden.json"), JSON.stringify({ reference: "maplibre-gl 6.16.0", worst, rows }, null, 2) + "\n");
const bad = rows.filter((r) => !((r.px ?? 0) <= 1e-6 && (r.deg ?? 0) <= 1e-7 && (r.zoom ?? 0) <= 1e-8 && (r.ms ?? 0) <= 1e-5 && (r.rel ?? 0) <= 1e-6 && (r.tiles ?? 0) === 0));
for (const r of bad.slice(0, 40)) console.log("beyond tolerance:", JSON.stringify(r));
if (bad.length) process.exitCode = 1;
