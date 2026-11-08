// The analysis tab: places' Voronoi cells classed by area (field editor columns, jenks as a `step`
// the legend lists), the shortest way along the drawn roads, and what the center sees (GSI's DEM:
// a viewshed on a canvas source, a line of sight to a click).
import { classBreaks, classStep, load, loadDem } from "mbmap/analysis";
import { createFieldEditor } from "mbmap/ui";
import { PLACES } from "./places.js";
import { DEM_TILES } from "./style.js";
import { tileLines } from "./tile-lines.js";

/** Where the cells are made: central Tokyo. */
export const CELLS_BBOX = [139.68, 35.62, 139.83, 35.74];
/** The classes' colors, lightest first. */
export const CLASS_COLORS = ["#fef0d9", "#fdcc8a", "#fc8d59", "#e34a33", "#b30000"];
/** How far the viewshed reaches, in meters. */
export const SIGHT_METERS = 2000;
const VISIBLE = 255;
const HIDDEN = 128;
// About a degree of latitude in meters, and how far past the viewshed's radius its DEM grid reaches.
const METERS_PER_DEGREE = 111320;
const DEM_MARGIN = 1.1;

const empty = () => ({ type: "FeatureCollection", features: [] });
const line = (coordinates, properties = {}) => ({ type: "Feature", properties, geometry: { type: "LineString", coordinates } });
const point = (coordinates, properties = {}) => ({ type: "Feature", properties, geometry: { type: "Point", coordinates } });

/**
 * `cells` `{ breaks, count }`, `route` `{ length, steps }`, `sight` `{ visible }` (share seen), `target` `{ visible, blockedAt }`
 * (each null, "loading" or `{ error }`); `picking` "route" | "sight" | null while clicks go here; route `points`; last `error`.
 */
function initial() {
  return { cells: null, route: null, sight: null, target: null, picking: null, points: [], error: null };
}

/** The tab's tools on `map`; `beforePick` runs before clicks start going to it (to stop drawing and measuring). */
export function createAnalysis(map, beforePick = () => {}) {
  const listeners = new Set();
  const data = { "analysis-cells": empty(), "analysis-route": empty(), "analysis-sight": empty() };
  const canvas = document.createElement("canvas");
  let viewshed = null;
  let grid = null;
  let observer = null;
  let cellPaint = null;
  const a = {
    state: initial(),
    subscribe(f) {
      listeners.add(f);
      return () => listeners.delete(f);
    },
    set(patch) {
      a.state = { ...a.state, ...patch };
      for (const f of [...listeners]) f(a.state);
    },
  };
  const setData = (id, fc) => {
    data[id] = fc;
    map.getSource(id)?.setData(fc);
  };
  // A new style drops what the tab added: put it back, under the places and the radius ring (ring.js).
  const keep = () => {
    if (!map.getStyle()) return;
    // Asked at each layer: adding one fires styledata, which may bring the ring back meanwhile.
    const below = () => ["radius-ring", "places"].find((id) => map.getLayer(id));
    for (const id of Object.keys(data)) if (!map.getSource(id)) map.addSource(id, { type: "geojson", data: data[id] });
    if (cellPaint && !map.getLayer("analysis-cells")) {
      map.addLayer({ id: "analysis-cells", type: "fill", source: "analysis-cells", paint: { "fill-color": cellPaint, "fill-opacity": 0.6 } }, below());
      map.addLayer({ id: "analysis-cells-line", type: "line", source: "analysis-cells", paint: { "line-color": "#7a2e14", "line-width": 1 } }, below());
    }
    if (viewshed && !map.getSource("analysis-viewshed")) {
      const [w, s, e, n] = viewshed.bounds;
      map.addSource("analysis-viewshed", { type: "canvas", canvas, coordinates: [[w, n], [e, n], [e, s], [w, s]], animate: false });
      map.addLayer({ id: "analysis-viewshed", type: "raster", source: "analysis-viewshed", paint: { "raster-opacity": 0.85 } }, below());
    }
    if (!map.getLayer("analysis-route")) {
      map.addLayer({ id: "analysis-route", type: "line", source: "analysis-route", filter: ["==", ["geometry-type"], "LineString"], paint: { "line-color": "#1f6feb", "line-width": 5, "line-opacity": 0.85 } }, below());
      map.addLayer({ id: "analysis-route-end", type: "circle", source: "analysis-route", filter: ["==", ["geometry-type"], "Point"], paint: { "circle-radius": 6, "circle-color": "#1f6feb", "circle-stroke-color": "#ffffff", "circle-stroke-width": 2 } }, below());
    }
    if (!map.getLayer("analysis-sight")) {
      map.addLayer({ id: "analysis-sight", type: "line", source: "analysis-sight", filter: ["==", ["geometry-type"], "LineString"], paint: { "line-color": ["case", ["get", "visible"], "#2da44e", "#cf222e"], "line-width": 3, "line-dasharray": [2, 1] } }, below());
      map.addLayer({ id: "analysis-sight-point", type: "circle", source: "analysis-sight", filter: ["==", ["geometry-type"], "Point"], paint: { "circle-radius": 5, "circle-color": ["case", ["get", "blocked"], "#cf222e", "#2da44e"], "circle-stroke-color": "#ffffff", "circle-stroke-width": 2 } }, below());
    }
  };
  map.on("styledata", keep);
  keep();
  const removeLayers = (...ids) => {
    for (const id of ids) if (map.getLayer(id)) map.removeLayer(id);
  };
  const failed = (err, patch) => a.set({ ...patch, error: err.message ?? String(err) });

  /** The places' Voronoi cells in CELLS_BBOX, an area column by function and one in km² by expression, classed by jenks. */
  a.classify = async () => {
    a.set({ cells: "loading", error: null });
    let points = null;
    let cells = null;
    try {
      const [w, s, e, n] = CELLS_BBOX;
      const inside = PLACES.features.filter(({ geometry: { coordinates: [x, y] } }) => x >= w && x <= e && y >= s && y <= n);
      points = await load({ type: "FeatureCollection", features: inside });
      cells = await points.voronoi(CELLS_BBOX);
      const [areas, fc] = await Promise.all([cells.areas(), cells.toGeoJSON()]);
      setData("analysis-cells", fc);
      const fields = createFieldEditor(map, { source: "analysis-cells" });
      const byName = new Map(fc.features.map((f, i) => [f.properties.name, areas[i]]));
      await fields.calculate("面積", (row) => byName.get(row.properties.name) ?? null);
      await fields.calculate("面積_km2", ["/", ["round", ["/", ["get", "面積"], 10000]], 100]);
      data["analysis-cells"] = await map.getSource("analysis-cells").getData();
      const values = data["analysis-cells"].features.map((f) => f.properties["面積_km2"]);
      const breaks = classBreaks(values, CLASS_COLORS.length, "jenks") ?? classBreaks(values, CLASS_COLORS.length, "quantile");
      cellPaint = classStep(["get", "面積_km2"], breaks, CLASS_COLORS);
      removeLayers("analysis-cells-line", "analysis-cells");
      keep();
      a.set({ cells: { breaks, count: values.length } });
    } catch (err) {
      failed(err, { cells: null });
    } finally {
      points?.dispose();
      cells?.dispose();
    }
  };
  a.clearCells = () => {
    cellPaint = null;
    removeLayers("analysis-cells-line", "analysis-cells");
    setData("analysis-cells", empty());
    a.set({ cells: null });
  };

  /** Clicks go to `mode` ("route": a start and an end; "sight": targets), or nowhere with null. */
  a.pick = (mode) => {
    if (mode) beforePick();
    a.set({ picking: mode, points: mode === "route" ? [] : a.state.points });
  };
  /** A click on the map at `lngLat` while picking. */
  a.click = (lngLat) => {
    const at = [lngLat.lng, lngLat.lat];
    if (a.state.picking === "route") {
      const points = [...a.state.points, at];
      setData("analysis-route", { type: "FeatureCollection", features: points.map((p) => point(p)) });
      a.set({ points });
      if (points.length === 2) void route(points[0], points[1]);
    } else if (a.state.picking === "sight") {
      void sightTo(at);
    }
  };

  // The road vertex nearest `p` (in degrees, which is near enough for snapping).
  const nearestVertex = (lines, p) => {
    let best = null;
    let d = Infinity;
    for (const l of lines) {
      for (const c of l.geometry.coordinates) {
        const dd = (c[0] - p[0]) ** 2 + (c[1] - p[1]) ** 2;
        if (dd < d) [best, d] = [c, dd];
      }
    }
    return best;
  };
  /** The shortest way from `from` to `to` along the roads of the drawn tiles. */
  const route = async (from, to) => {
    a.set({ route: "loading", picking: null, error: null });
    let roads = null;
    let network = null;
    try {
      const features = await map.querySourceFeatures("gsi", { sourceLayer: "road" });
      const lines = tileLines(features).map((c) => line(c));
      const [start, end] = [nearestVertex(lines, from), nearestVertex(lines, to)];
      if (!start || !end) return a.set({ route: { error: "道路が見つかりません" } });
      roads = await load({ type: "FeatureCollection", features: lines });
      network = await roads.network({ tolerance: 1e-5 });
      const found = await network.route(start, end);
      setData("analysis-route", { type: "FeatureCollection", features: [...(found ? [line(found.path)] : []), point(start), point(end)] });
      a.set({ route: found ? { length: found.weight * 1000, steps: found.path.length - 1 } : { error: "つながる道がありません" } });
    } catch (err) {
      failed(err, { route: null });
    } finally {
      roads?.dispose();
      network?.dispose();
    }
  };
  a.clearRoute = () => {
    setData("analysis-route", empty());
    a.set({ route: null, points: [], picking: a.state.picking === "route" ? null : a.state.picking });
  };

  /** The cells seen from `center` within SIGHT_METERS (2 m above the ground), drawn on a canvas source. */
  a.viewshed = async (center) => {
    a.set({ sight: "loading", target: null, error: null });
    try {
      const dy = (SIGHT_METERS * DEM_MARGIN) / METERS_PER_DEGREE;
      const dx = dy / Math.cos((center.lat * Math.PI) / 180);
      grid?.dispose();
      grid = null;
      observer = [center.lng, center.lat];
      grid = await loadDem(DEM_TILES, { zoom: 14, bounds: [center.lng - dx, center.lat - dy, center.lng + dx, center.lat + dy], encoding: "gsi" });
      const r = await grid.viewshed(observer, { maxDistance: SIGHT_METERS, visibleValue: VISIBLE, invisibleValue: HIDDEN, outOfRangeValue: 0 });
      Object.assign(canvas, { width: r.width, height: r.height });
      const ctx = canvas.getContext("2d");
      const image = ctx.createImageData(r.width, r.height);
      let seen = 0;
      let inRange = 0;
      r.values.forEach((v, i) => {
        if (v === 0) return;
        inRange++;
        if (v === VISIBLE) seen++;
        image.data.set(v === VISIBLE ? [46, 164, 78, 150] : [40, 40, 40, 90], i * 4);
      });
      ctx.putImageData(image, 0, 0);
      viewshed = r;
      removeLayers("analysis-viewshed");
      if (map.getSource("analysis-viewshed")) map.removeSource("analysis-viewshed");
      keep();
      setData("analysis-sight", { type: "FeatureCollection", features: [point(observer, { blocked: false })] });
      a.set({ sight: { visible: inRange ? seen / inRange : 0 } });
    } catch (err) {
      failed(err, { sight: null });
    }
  };
  /** Whether `to` can be seen from the viewshed's observer. */
  const sightTo = async (to) => {
    if (!grid) return a.set({ target: { error: "先に「可視域」を押す" } });
    const [w, s, e, n] = grid.bounds;
    if (to[0] < w || to[0] > e || to[1] < s || to[1] > n) return a.set({ target: { error: "範囲の外です" } });
    try {
      const r = await grid.lineOfSight(observer, to);
      const marks = [point(observer, { blocked: false }), point(to, { blocked: !r.visible }), ...(r.blockedAt ? [point(r.blockedAt, { blocked: true })] : [])];
      setData("analysis-sight", { type: "FeatureCollection", features: [line([observer, to], { visible: r.visible }), ...marks] });
      a.set({ target: r });
    } catch (err) {
      failed(err, { target: null });
    }
  };
  a.clearSight = () => {
    grid?.dispose();
    grid = viewshed = observer = null;
    removeLayers("analysis-viewshed");
    if (map.getSource("analysis-viewshed")) map.removeSource("analysis-viewshed");
    setData("analysis-sight", empty());
    a.set({ sight: null, target: null, picking: a.state.picking === "sight" ? null : a.state.picking });
  };

  a.destroy = () => {
    map.off("styledata", keep);
    grid?.dispose();
    listeners.clear();
  };
  window.__analysis = a;
  return a;
}

const km2 = (v) => `${v.toFixed(2)} km²`;
const meters = (v) => (v >= 1000 ? `${(v / 1000).toFixed(2)} km` : `${Math.round(v)} m`);

/** A legend label for the cells' classes, or undefined for other layers. */
export function cellsLegendLabel(layer, category) {
  if (layer.id !== "analysis-cells" || !category.range) return undefined;
  const [from, to] = category.range;
  return from === null ? `${km2(to)} 未満` : to === null ? `${km2(from)} 以上` : `${km2(from)} 〜 ${km2(to)}`;
}

/** Each tool's buttons as [label, action, pressed (or undefined), enabled]; `center()` is the map's center. */
export function analysisActions(a, s, center) {
  return {
    cells: [
      ["面積で塗り分け", () => a.classify(), undefined, s.cells !== "loading"],
      ["消す", () => a.clearCells(), undefined, Boolean(s.cells)],
    ],
    route: [
      ["2 点をクリック", () => a.pick(s.picking === "route" ? null : "route"), s.picking === "route", s.route !== "loading"],
      ["消す", () => a.clearRoute(), undefined, Boolean(s.route) || s.points.length > 0],
    ],
    sight: [
      ["中心からの可視域", () => a.viewshed(center()), undefined, s.sight !== "loading"],
      ["見通しをクリック", () => a.pick(s.picking === "sight" ? null : "sight"), s.picking === "sight", Boolean(s.sight) && s.sight !== "loading"],
      ["消す", () => a.clearSight(), undefined, Boolean(s.sight)],
    ],
  };
}

/** Each tool's readout as [term, description] rows. */
export function analysisRows(s) {
  const cells =
    s.cells === "loading" ? [["", "計算中…"]] : s.cells ? [["地点", `${s.cells.count}`], ["区切り", s.cells.breaks.map((b) => b.toFixed(2)).join(" / ")]] : [["—", "地点のボロノイ領域を面積の 5 階級（自然分類）で塗る"]];
  const route =
    s.route === "loading" ? [["", "計算中…"]]
    : s.route?.error ? [["—", s.route.error]]
    : s.route ? [["距離", meters(s.route.length)], ["区間", `${s.route.steps}`]]
    : s.picking === "route" ? [["", `${s.points.length === 0 ? "出発地" : "目的地"}をクリック`]]
    : [["—", "表示している道路で最短経路を探す"]];
  const sight = [];
  if (s.sight === "loading") sight.push(["", "計算中…"]);
  else if (s.sight) sight.push(["見える範囲", `${Math.round(s.sight.visible * 100)}%（半径 ${meters(SIGHT_METERS)}）`]);
  else sight.push(["—", "地図の中心（地上 2 m）から見える範囲"]);
  if (s.target?.error) sight.push(["見通し", s.target.error]);
  else if (s.target) sight.push(["見通し", s.target.visible ? "見える" : "見えない（赤い点で遮られる）"]);
  else if (s.picking === "sight") sight.push(["", "見たい地点をクリック"]);
  return { cells, route, sight, error: s.error };
}

/**
 * Sends clicks to the tab while it picks, and stops its picking when `others` (the measurement and
 * the drawing) start; returns what stops both.
 */
export function routeAnalysisClicks(map, a, others) {
  const click = (e) => {
    if (a.state.picking) a.click(e.lngLat);
  };
  map.on("click", click);
  const stops = others.map((c) => c.subscribe((s) => s.mode && a.state.picking && a.pick(null)));
  return () => {
    map.off("click", click);
    for (const stop of stops) stop();
  };
}

const el = (tag, props = {}) => Object.assign(document.createElement(tag), props);

/** The tab drawn with plain DOM into `#analysis-*`. */
export function mountAnalysis(map, beforePick) {
  const a = createAnalysis(map, beforePick);
  const draw = (s) => {
    const actions = analysisActions(a, s, () => map.getCenter());
    const rows = analysisRows(s);
    for (const key of ["cells", "route", "sight"]) {
      document.getElementById(`analysis-${key}`).replaceChildren(
        ...actions[key].map(([label, f, pressed, enabled]) => {
          const b = el("button", { textContent: label, disabled: !enabled });
          if (pressed !== undefined) b.setAttribute("aria-pressed", String(pressed));
          b.addEventListener("click", f);
          return b;
        }),
      );
      document.getElementById(`analysis-${key}-rows`).replaceChildren(...rows[key].flatMap(([k, v]) => [el("dt", { textContent: k }), el("dd", { textContent: v })]));
    }
    const error = document.getElementById("analysis-error");
    error.hidden = !rows.error;
    error.textContent = rows.error ?? "";
  };
  a.subscribe(draw);
  draw(a.state);
  return a;
}
