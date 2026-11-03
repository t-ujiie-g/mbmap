// The scenes of style/golden.mjs: a style, a camera and the differences allowed (per-channel mean
// and 99th percentile, 0-255), set just above what was measured; `gap` names what mbmap lacks there.
const GSI = { type: "vector", tiles: ["{origin}/bench/fixtures/gsi-bvmap/{z}/{x}/{y}.pbf"], minzoom: 14, maxzoom: 14 };
const TOKYO = { center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 };
const bg = { id: "bg", type: "background", paint: { "background-color": "#f5f3ee" } };
const style = (layers, sources = { gsi: GSI }) => ({ version: 8, sources, layers: [bg, ...layers] });

// Seeded points around Tokyo, half of them in a few clumps.
function points(count) {
  let s = 11;
  const rand = () => ((s = (Math.imul(s, 1103515245) + 12345) >>> 0) / 4294967296);
  const clumps = Array.from({ length: 8 }, () => [139.6 + rand() * 0.3, 35.6 + rand() * 0.2]);
  const features = Array.from({ length: count }, (_, i) => {
    const [cx, cy] = i % 2 ? [139.6 + rand() * 0.3, 35.6 + rand() * 0.2] : clumps[i % clumps.length];
    const r = i % 2 ? 0 : 0.02;
    return { type: "Feature", properties: { i }, geometry: { type: "Point", coordinates: [cx + (rand() - 0.5) * r, cy + (rand() - 0.5) * r] } };
  });
  return { type: "FeatureCollection", features };
}
const CLUSTERED = { pts: { type: "geojson", data: points(3000), cluster: true, clusterRadius: 40, clusterMaxZoom: 14 } };
const isCluster = ["has", "point_count"];

export const SCENES = {
  fills: {
    style: style([
      { id: "water", type: "fill", source: "gsi", "source-layer": "waterarea", paint: { "fill-color": "#a8d4f0" } },
      { id: "building", type: "fill", source: "gsi", "source-layer": "building", paint: { "fill-color": "#d9c9b6", "fill-opacity": 0.7 } },
    ]),
    camera: TOKYO,
    limits: { mean: 0.05, p99: 1 },
  },
  outlines: {
    style: style([
      { id: "water", type: "fill", source: "gsi", "source-layer": "waterarea", paint: { "fill-color": "#a8d4f0", "fill-antialias": false } },
      { id: "building", type: "fill", source: "gsi", "source-layer": "building",
        paint: { "fill-color": "#ece6dc", "fill-outline-color": ["match", ["get", "ftCode"], 3103, "#8a6d4b", "#c9bba7"] } },
    ]),
    camera: TOKYO,
    limits: { mean: 0.05, p99: 1 },
  },
  lines: {
    style: style([
      { id: "road", type: "line", source: "gsi", "source-layer": "road", layout: { "line-cap": "round", "line-join": "round" },
        paint: { "line-color": ["match", ["get", "rdCtg"], [0, 1], "#e8a33b", "#ffffff"], "line-width": ["interpolate", ["exponential", 2], ["zoom"], 14, 1, 18, 16] } },
      { id: "rail", type: "line", source: "gsi", "source-layer": "railway", layout: { "line-cap": "butt" }, paint: { "line-color": "#555555", "line-width": 2 } },
    ]),
    camera: TOKYO,
    limits: { mean: 0.1, p99: 2 },
  },
  circles: {
    style: style([
      { id: "pt", type: "circle", source: "gsi", "source-layer": "symbol",
        paint: { "circle-radius": 4, "circle-color": "#3b6ed6", "circle-stroke-color": "#ffffff", "circle-stroke-width": 1.5 } },
    ]),
    camera: TOKYO,
    limits: { mean: 0.05, p99: 1 },
  },
  turned: {
    style: style([
      { id: "water", type: "fill", source: "gsi", "source-layer": "waterarea", paint: { "fill-color": "#a8d4f0" } },
      { id: "road", type: "line", source: "gsi", "source-layer": "road", paint: { "line-color": "#999999", "line-width": 3 } },
    ]),
    camera: { center: [139.7671, 35.6812], zoom: 15.4, bearing: 30, pitch: 45 },
    limits: { mean: 0.7, p99: 21 },
  },
  // Data-driven paint per vertex: a radius and a color continuous in the labels' `arrngAgl`
  // (angles, hundreds of values past the 64 groups paint used to split into), and a width varying
  // with zoom and `rdCtg` seen at z16.5 on z14 tiles (each zoom stop's value is kept per vertex).
  "data-circles": {
    style: style([
      { id: "pt", type: "circle", source: "gsi", "source-layer": "label",
        paint: {
          "circle-radius": ["interpolate", ["linear"], ["get", "arrngAgl"], 0, 2, 360, 9],
          "circle-color": ["interpolate", ["linear"], ["get", "arrngAgl"], 0, "#2b83ba", 360, "#d7191c"],
          "circle-stroke-color": "#ffffff", "circle-stroke-width": ["step", ["get", "arrngAgl"], 0, 180, 1.5],
        } },
    ]),
    camera: TOKYO,
    limits: { mean: 0.05, p99: 1 },
  },
  "data-lines": {
    style: style([
      { id: "road", type: "line", source: "gsi", "source-layer": "road", layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": ["match", ["get", "rdCtg"], [0, 1], "#e8a33b", "#9aa0a6"],
          "line-width": ["interpolate", ["exponential", 2], ["zoom"], 14, ["match", ["get", "rdCtg"], [0, 1], 3, 1], 18, ["match", ["get", "rdCtg"], [0, 1], 32, 12]],
          "line-opacity": ["match", ["get", "rdCtg"], 2, 0.6, 1],
        } },
    ]),
    camera: { center: [139.7671, 35.6812], zoom: 16.5, bearing: 0, pitch: 0 },
    limits: { mean: 0.05, p99: 1 },
  },
  // A clustered GeoJSON source: circles sized and colored by `point_count`, and the points left alone.
  clusters: {
    style: style([
      { id: "clusters", type: "circle", source: "pts", filter: isCluster,
        paint: {
          "circle-color": ["step", ["get", "point_count"], "#51bbd6", 10, "#f1a340", 50, "#e7298a"],
          "circle-radius": ["step", ["get", "point_count"], 8, 10, 12, 50, 18],
          "circle-stroke-color": "#ffffff", "circle-stroke-width": 1,
        } },
      { id: "single", type: "circle", source: "pts", filter: ["!", isCluster], paint: { "circle-color": "#11b4da", "circle-radius": 3 } },
    ], CLUSTERED),
    camera: { center: [139.75, 35.7], zoom: 11, bearing: 0, pitch: 0 },
    limits: { mean: 0.07, p99: 1 },
  },
  expressions: {
    style: style([
      { id: "pt", type: "circle", source: "gsi", "source-layer": "label", filter: [">", ["to-number", ["get", "orgGILvl"]], 0],
        paint: {
          "circle-radius": ["+", ["*", ["sqrt", ["get", "arrngAgl"]], 0.5], 3],
          "circle-color": ["interpolate-hcl", ["linear"], ["get", "arrngAgl"], 0, "#2b83ba", 360, "#d7191c"],
          "circle-stroke-color": "#ffffff", "circle-stroke-width": ["let", "a", ["get", "arrngAgl"], ["case", [">", ["%", ["var", "a"], 180], 0], 1.5, 0]],
        } },
    ]),
    camera: TOKYO,
    limits: { mean: 0.05, p99: 1 },
  },
  legacy: {
    style: style([
      { id: "road", type: "line", source: "gsi", "source-layer": "road", filter: ["in", "rdCtg", 0, 1, 2], layout: { "line-cap": "round", "line-join": "round" },
        paint: {
          "line-color": { property: "rdCtg", type: "categorical", stops: [[0, "#e8a33b"], [1, "#d08c2b"]], default: "#9aa0a6" },
          "line-width": { base: 2, stops: [[14, 1], [18, 16]] },
        } },
      { id: "rail", type: "line", source: "gsi", "source-layer": "railway", filter: ["all", ["has", "snglDbl"], ["!=", "$type", "Polygon"]], paint: { "line-color": "#555555", "line-width": 2 } },
    ]),
    camera: TOKYO,
    limits: { mean: 0.05, p99: 1 },
  },
};
