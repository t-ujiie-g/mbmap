// The elevation profile of a finished distance measurement (mbmap/ui, heights
// from GSI's DEM by mbmap/analysis's `sampleDem`), drawn as SVG; the point under
// the chart's pointer is a dot on the map (`map.track`).
import { sampleDem } from "mbmap/analysis";
import { measure } from "mbmap/geodesic";
import { createProfile, formatLength } from "mbmap/ui";
import { DEM_TILES } from "./style.js";

export const CHART = { width: 260, height: 110, pad: 4 };

/** The profile of `measurement`'s line once it is finished in distance mode; cleared otherwise. */
export function createShowcaseProfile(measurement) {
  const profile = createProfile({ measure, elevation: (p) => sampleDem(DEM_TILES, p, { encoding: "gsi" }) });
  let line = null;
  const follow = (s) => {
    const next = s.mode === "distance" && s.finished && s.positions.length > 1 ? s.positions : null;
    if (next === line) return;
    line = next;
    if (next) void profile.setLine(next);
    else profile.clear();
  };
  const stop = measurement.subscribe(follow);
  follow(measurement.state);
  window.__profile = profile;
  return { profile, stop };
}

/**
 * The chart of a profile state in `CHART`'s box: `line` and `area` as SVG paths (gaps where the DEM
 * has no data), the scale's labels, and the pointed sample's `x`, `y` (null for none).
 */
export function chartOf(s) {
  const { width, height, pad } = CHART;
  if (s.distances.length < 2 || !Number.isFinite(s.min)) return null;
  const span = Math.max(s.max - s.min, 1);
  const x = (d) => pad + (d / s.length) * (width - 2 * pad);
  const y = (e) => pad + (1 - (e - s.min) / span) * (height - 2 * pad);
  let line = "";
  let pen = false;
  s.distances.forEach((d, i) => {
    const e = s.elevations[i];
    if (Number.isNaN(e)) return void (pen = false);
    line += `${pen ? "L" : "M"}${x(d).toFixed(1)},${y(e).toFixed(1)}`;
    pen = true;
  });
  const area = `${line}L${x(s.length).toFixed(1)},${height - pad}L${pad},${height - pad}Z`;
  const a = s.active;
  const at = a >= 0 && !Number.isNaN(s.elevations[a]) ? { x: x(s.distances[a]), y: y(s.elevations[a]) } : null;
  return { line, area, at, top: `${Math.round(s.max)} m`, bottom: `${Math.round(s.min)} m` };
}

/** The distance along the profile under `clientX` on a chart element. */
export function distanceAt(s, element, clientX) {
  const r = element.getBoundingClientRect();
  const f = (clientX - r.left) / r.width;
  return ((f * CHART.width - CHART.pad) / (CHART.width - 2 * CHART.pad)) * s.length;
}

/** The figures under the chart. */
export function profileRows(s) {
  if (s.loading) return [["", "標高を読んでいます…"]];
  if (s.error) return [["", s.error]];
  if (s.distances.length === 0) return [["—", "距離を測ると断面図が出ます"]];
  const rows = [["長さ", formatLength(s.length)], ["最高", `${s.max.toFixed(1)} m`], ["最低", `${s.min.toFixed(1)} m`], ["登り", `${s.gain.toFixed(1)} m`], ["下り", `${s.loss.toFixed(1)} m`]];
  if (s.active >= 0) rows.push(["ここ", `${formatLength(s.distances[s.active])}、${s.elevations[s.active].toFixed(1)} m`]);
  return rows;
}

/** A dot on the map at the pointed sample, as a child of `parent` (which covers the map); returns its removal. */
export function trackProfile(map, profile, parent) {
  const dot = document.createElement("div");
  dot.className = "profile-dot";
  dot.hidden = true;
  parent.append(dot);
  let tracker = null;
  const draw = (s) => {
    const p = s.active >= 0 ? s.path[s.active] : null;
    dot.hidden = !p;
    if (!p) return;
    const at = { lng: p[0], lat: p[1] };
    if (tracker) tracker.setLngLat(at);
    else tracker = map.track(at, ({ x, y }) => (dot.style.transform = `translate(${x}px, ${y}px)`));
  };
  const stop = profile.subscribe(draw);
  return () => {
    stop();
    tracker?.remove();
    dot.remove();
  };
}

const SVG = "http://www.w3.org/2000/svg";
const svg = (name, attrs = {}) => {
  const e = document.createElementNS(SVG, name);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  return e;
};

/** The chart and figures in `#profile` for the plain-DOM examples. */
export function mountProfile(map, measurement) {
  const { profile } = createShowcaseProfile(measurement);
  trackProfile(map, profile, document.body);
  const figure = document.getElementById("profile");
  const chart = svg("svg", { viewBox: `0 0 ${CHART.width} ${CHART.height}`, class: "profile-chart", role: "img", "aria-label": "断面図" });
  const dl = document.createElement("dl");
  figure.replaceChildren(chart, dl);
  chart.addEventListener("pointermove", (e) => profile.highlight(distanceAt(profile.state, chart, e.clientX)));
  chart.addEventListener("pointerleave", () => profile.highlight(null));
  const draw = (s) => {
    const c = chartOf(s);
    chart.replaceChildren();
    chart.hidden = !c;
    if (c) {
      chart.append(svg("path", { d: c.area, class: "profile-area" }), svg("path", { d: c.line, class: "profile-line" }));
      const top = svg("text", { x: CHART.pad + 2, y: 12, class: "profile-label" });
      top.textContent = c.top;
      const bottom = svg("text", { x: CHART.pad + 2, y: CHART.height - 8, class: "profile-label" });
      bottom.textContent = c.bottom;
      chart.append(top, bottom);
      if (c.at) chart.append(svg("circle", { cx: c.at.x, cy: c.at.y, r: 3.5, class: "profile-at" }));
    }
    dl.replaceChildren(...profileRows(s).flatMap(([k, v]) => [Object.assign(document.createElement("dt"), { textContent: k }), Object.assign(document.createElement("dd"), { textContent: v })]));
  };
  profile.subscribe(draw);
  draw(profile.state);
  return profile;
}
