// The scenes of style/golden.mjs: a style, a camera and the differences allowed (per-channel mean
// and 99th percentile, 0-255), set just above what was measured; `gap` names what mbmap lacks there.
const GSI = { type: "vector", tiles: ["{origin}/bench/fixtures/gsi-bvmap/{z}/{x}/{y}.pbf"], minzoom: 14, maxzoom: 14 };
const TOKYO = { center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 };
const bg = { id: "bg", type: "background", paint: { "background-color": "#f5f3ee" } };
const style = (layers, sources = { gsi: GSI }) => ({ version: 8, sources, layers: [bg, ...layers] });

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
  // Dashes (MapLibre's line_sdf over the line atlas): a railway's white dashes over its casing, butt
  // and round dash ends, boundaries; at a fractional zoom the pattern is measured at the integer one.
  dashes: {
    style: style([
      { id: "rail-casing", type: "line", source: "gsi", "source-layer": "railway", paint: { "line-color": "#555555", "line-width": 4 } },
      { id: "rail", type: "line", source: "gsi", "source-layer": "railway", paint: { "line-color": "#ffffff", "line-width": 2.5, "line-dasharray": [3, 3] } },
      { id: "road", type: "line", source: "gsi", "source-layer": "road", layout: { "line-cap": "round", "line-join": "round" },
        paint: { "line-color": "#c06030", "line-width": 2, "line-dasharray": [0.5, 2] } },
      { id: "boundary", type: "line", source: "gsi", "source-layer": "boundary", paint: { "line-color": "#7a4ea3", "line-width": 1.5, "line-dasharray": [4, 1, 1, 1] } },
    ]),
    camera: TOKYO,
    limits: { mean: 0.05, p99: 1 },
  },
  "dashes-zoomed": {
    style: style([
      { id: "rail", type: "line", source: "gsi", "source-layer": "railway",
        paint: { "line-color": "#333333", "line-width": ["interpolate", ["linear"], ["zoom"], 15, 2, 17, 6],
          "line-dasharray": ["step", ["zoom"], ["literal", [2, 2]], 16, ["literal", [5, 1]]] } },
      { id: "road", type: "line", source: "gsi", "source-layer": "road",
        paint: { "line-color": ["match", ["get", "rdCtg"], [0, 1], "#e8a33b", "#9aa0a6"], "line-width": 3, "line-dasharray": [1, 1] } },
    ]),
    camera: { center: [139.7671, 35.6812], zoom: 16.6, bearing: 0, pitch: 0 },
    limits: { mean: 0.05, p99: 1 },
  },
};
