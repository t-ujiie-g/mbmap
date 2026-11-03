// The scenes of style/golden.mjs: a style, a camera and the differences allowed (per-channel mean
// and 99th percentile, 0-255), set just above what was measured; `gap` names what mbmap lacks there.
const GSI = { type: "vector", tiles: ["{origin}/bench/fixtures/gsi-bvmap/{z}/{x}/{y}.pbf"], minzoom: 14, maxzoom: 14 };
const TOKYO = { center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 };
const bg = { id: "bg", type: "background", paint: { "background-color": "#f5f3ee" } };
const style = (layers, sources = { gsi: GSI }) => ({ version: 8, sources, layers: [bg, ...layers] });
// style/sprite.mjs's sheets: dots 12 px, stripes 16 x 8 (translucent), checker 10, odd 7 x 5.
const SPRITE = "{origin}/bench/dist/style/sprite";
const patterned = (layers) => ({
  ...style(layers),
  sprite: SPRITE,
  layers: [{ id: "bg", type: "background", paint: { "background-pattern": "checker" } }, ...layers],
});
const PATTERN_LAYERS = [
  { id: "water", type: "fill", source: "gsi", "source-layer": "waterarea", paint: { "fill-pattern": "dots" } },
  { id: "building", type: "fill", source: "gsi", "source-layer": "building",
    paint: { "fill-pattern": ["match", ["get", "ftCode"], 3103, "stripes", "odd"], "fill-opacity": 0.8 } },
  { id: "structure", type: "fill", source: "gsi", "source-layer": "structurea", paint: { "fill-pattern": "checker", "fill-outline-color": "#333333" } },
];

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
const POINTS = { pts: { type: "geojson", data: points(3000) } };
// Lines winding across tile borders around Tokyo Station, for line metrics: a zigzag and a loop.
const zigzag = (lat) => Array.from({ length: 13 }, (_, i) => [139.70 + i * 0.012, lat + (i % 2) * 0.012]);
const loop = Array.from({ length: 41 }, (_, i) => [139.767 + 0.03 * Math.cos((i / 40) * 2 * Math.PI), 35.681 + 0.024 * Math.sin((i / 40) * 2 * Math.PI)]);
const ROUTES = {
  routes: {
    type: "geojson", lineMetrics: true,
    data: { type: "FeatureCollection", features: [
      { type: "Feature", properties: { k: 1 }, geometry: { type: "LineString", coordinates: zigzag(35.66) } },
      { type: "Feature", properties: { k: 2 }, geometry: { type: "MultiLineString", coordinates: [zigzag(35.69), loop] } },
    ] },
  },
};

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
  // Line gradients over line metrics (MapLibre's line_gradient and renderColorRamp): an
  // interpolated ramp with a translucent end, and a step ramp.
  gradients: {
    style: style([
      { id: "smooth", type: "line", source: "routes", filter: ["==", ["get", "k"], 1], layout: { "line-cap": "round", "line-join": "round" },
        paint: { "line-width": 8, "line-gradient": ["interpolate", ["linear"], ["line-progress"], 0, "#2b83ba", 0.5, "#ffffbf", 1, "rgba(215, 25, 28, 0.4)"] } },
      { id: "steps", type: "line", source: "routes", filter: ["==", ["get", "k"], 2],
        paint: { "line-width": 5, "line-opacity": 0.9, "line-gradient": ["step", ["line-progress"], "#1a9641", 0.3, "#fdae61", 0.7, "#7b3294"] } },
    ], ROUTES),
    camera: { center: [139.767, 35.678], zoom: 12.5, bearing: 0, pitch: 0 },
    limits: { mean: 0.07, p99: 1 },
  },
  // Patterns from a sprite (MapLibre's fill_pattern, fill_outline_pattern, background_pattern):
  // a constant and a per-feature pattern, an outline in the pattern and one in a color, a
  // translucent background; then the @2x sheet on a 2x screen at a fractional zoom.
  patterns: {
    style: patterned(PATTERN_LAYERS),
    camera: TOKYO,
    limits: { mean: 0.05, p99: 1 },
  },
  "patterns-2x": {
    style: patterned(PATTERN_LAYERS),
    camera: { center: [139.7671, 35.6812], zoom: 15.6, bearing: 0, pitch: 0 },
    dpr: 2,
    limits: { mean: 0.05, p99: 1 },
  },
  // Heatmaps (kernels into a quarter-size float texture, colored by a 256-px ramp of density): the
  // default ramp over GeoJSON points and over a tile's labels, then a step ramp with data-driven
  // radii on a turned and pitched map.
  heatmap: {
    style: style([
      { id: "heat", type: "heatmap", source: "pts",
        paint: {
          "heatmap-weight": ["interpolate", ["linear"], ["get", "i"], 0, 0.2, 3000, 2],
          "heatmap-radius": ["interpolate", ["linear"], ["zoom"], 9, 6, 13, 30],
          "heatmap-intensity": ["interpolate", ["linear"], ["zoom"], 9, 0.5, 13, 2],
          "heatmap-opacity": 0.85,
        } },
    ], POINTS),
    camera: { center: [139.75, 35.7], zoom: 11, bearing: 0, pitch: 0 },
    limits: { mean: 0.5, p99: 5 },
    gap: "GeoJSON tiles of extent 4096 (MapLibre's 8192) move points up to 1/16 px, about 1% of the density",
  },
  "heatmap-tiles": {
    style: style([
      { id: "heat", type: "heatmap", source: "gsi", "source-layer": "label",
        paint: { "heatmap-weight": ["interpolate", ["linear"], ["get", "arrngAgl"], 0, 0.3, 360, 1.5], "heatmap-radius": 25 } },
    ]),
    camera: TOKYO,
    limits: { mean: 0.05, p99: 1 },
  },
  "heatmap-turned": {
    style: style([
      { id: "heat", type: "heatmap", source: "gsi", "source-layer": "label",
        paint: {
          "heatmap-radius": ["step", ["get", "arrngAgl"], 12, 90, 22, 270, 35],
          "heatmap-intensity": 4,
          "heatmap-color": ["step", ["heatmap-density"], "rgba(0, 0, 0, 0)", 0.05, "#fee5d9", 0.3, "#fcae91", 0.6, "#fb6a4a", 0.9, "#cb181d"],
          "heatmap-opacity": ["interpolate", ["linear"], ["zoom"], 14, 1, 16, 0.6],
        } },
    ]),
    camera: { center: [139.7671, 35.6812], zoom: 15.2, bearing: 25, pitch: 50 },
    limits: { mean: 0.05, p99: 1 },
  },
};
