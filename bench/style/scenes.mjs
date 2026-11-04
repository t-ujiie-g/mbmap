// The scenes of style/golden.mjs: a style, a camera and the differences allowed (per-channel mean
// and 99th percentile, 0-255), set just above what was measured; `gap` names what mbmap lacks there.
import { FUJI_DEM } from "../lib/fuji-terrain.mjs";

const GSI = { type: "vector", tiles: ["{origin}/bench/fixtures/gsi-bvmap/{z}/{x}/{y}.pbf"], minzoom: 14, maxzoom: 14 };
const TOKYO = { center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 };
const bg = { id: "bg", type: "background", paint: { "background-color": "#f5f3ee" } };
const style = (layers, sources = { gsi: GSI }) => ({ version: 8, sources, layers: [bg, ...layers] });
// style/sprite.mjs's sheets: dots 12 px and stripes 16 x 8 (both translucent), checker 10 and odd
// 7 x 5 (opaque), pin 14 x 18 and an SDF ring 20 px.
const SPRITE = "{origin}/bench/dist/style/sprite";
const patterned = (layers) => ({
  ...style(layers),
  sprite: SPRITE,
  layers: [{ id: "bg", type: "background", paint: { "background-pattern": "checker" } }, ...layers],
});
// GSI symbols as icons by their code: pins, dots at half opacity, SDF rings colored with halos.
const ICONS = (layout = {}) => ({
  ...style([
    { id: "pins", type: "symbol", source: "gsi", "source-layer": "symbol", filter: ["!=", ["get", "ftCode"], 3218],
      layout: { "icon-image": ["match", ["get", "ftCode"], 3211, "dots", "pin"], "icon-anchor": "bottom", ...layout },
      paint: { "icon-color": "#1f6fb2", "icon-halo-color": "#ffffff", "icon-halo-width": 2, "icon-opacity": ["match", ["get", "ftCode"], 3211, 0.5, 1] } },
    { id: "rings", type: "symbol", source: "gsi", "source-layer": "symbol", filter: ["==", ["get", "ftCode"], 3218],
      layout: { "icon-image": "ring", "icon-size": 1.2, ...layout }, paint: { "icon-color": "#2a9d4b", "icon-halo-color": "#333333", "icon-halo-width": 0.8, "icon-halo-blur": 0.5 } },
  ]),
  sprite: SPRITE,
});
const LINE_ICONS = {
  ...style([
    { id: "pins", type: "symbol", source: "gsi", "source-layer": "contour",
      layout: { "symbol-placement": "line", "symbol-spacing": 140, "icon-image": "pin", "icon-size": 1.2 } },
    { id: "rings", type: "symbol", source: "gsi", "source-layer": "contour",
      layout: { "symbol-placement": "line-center", "icon-image": "ring", "icon-rotation-alignment": "viewport" },
      paint: { "icon-color": "#7a4fb0", "icon-halo-color": "#ffffff", "icon-halo-width": 1.5 } },
  ]),
  sprite: SPRITE,
};
// GSI labels with a little Latin in them (so fonts' weights show) drawn with MapLibre's symbol_sdf.
const TEXT = (layout = {}, paint = {}) => style([
  { id: "labels", type: "symbol", source: "gsi", "source-layer": "label",
    layout: { "text-field": ["concat", "St ", ["get", "knj"]], "text-font": ["Noto Sans Bold"], "text-size": 13, "text-max-width": 8, ...layout },
    paint: { "text-color": "#1d3557", "text-halo-color": "#ffffff", "text-halo-width": 1.5, "text-halo-blur": 1, ...paint } },
]);
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
const fixture = (x, y) => `{origin}/bench/fixtures/gsi-std/14/${x}/${y}.png`;
const IMAGES = style([
  { id: "flat", type: "raster", source: "flat", paint: { "raster-opacity": 0.85 } },
  { id: "tilted", type: "raster", source: "tilted", paint: { "raster-hue-rotate": 90, "raster-saturation": 0.4, "raster-contrast": 0.2 } },
  { id: "steep", type: "raster", source: "steep", paint: { "raster-brightness-min": 0.2, "raster-resampling": "nearest" } },
], {
  flat: { type: "image", url: fixture(14552, 6451), coordinates: [[139.755, 35.69], [139.772, 35.69], [139.772, 35.676], [139.755, 35.676]] },
  tilted: { type: "image", url: fixture(14553, 6450), coordinates: [[139.768, 35.689], [139.785, 35.687], [139.79, 35.672], [139.765, 35.674]] },
  steep: { type: "image", url: fixture(14552, 6452), coordinates: [[139.758, 35.674], [139.762, 35.674], [139.778, 35.664], [139.744, 35.664]] },
});

// The Mt Fuji DEM as Terrarium (both engines read it), seen at zoom 11.8 so both draw its z12 tiles
// as they are; the hillshade methods and color relief over it.
const FUJI = { center: [138.7793, 35.3174], zoom: 11.8, bearing: 0, pitch: 0 };
const dem = (layers) => style(layers, { dem: FUJI_DEM });
const hillshade = (paint) => dem([{ id: "hillshade", type: "hillshade", source: "dem", paint }]);
const RELIEF = ["interpolate", ["linear"], ["elevation"], 0, "#1a9641", 800, "#a6d96a", 1600, "#ffffbf", 2400, "#fdae61", 3200, "#d7191c", 3776, "rgba(255, 255, 255, 0.6)"];

export const SCENES = {
  fills: {
    style: style([
      { id: "water", type: "fill", source: "gsi", "source-layer": "waterarea", paint: { "fill-color": "#a8d4f0" } },
      { id: "building", type: "fill", source: "gsi", "source-layer": "building", paint: { "fill-color": "#d9c9b6", "fill-opacity": 0.7 } },
    ]),
    camera: TOKYO,
    limits: { mean: 0.05, p99: 1 },
  },
  // A global-state default, a collator in a filter, split / join / is-supported-script in paint.
  "expressions-strings": {
    style: {
      ...style([
        { id: "building", type: "fill", source: "gsi", "source-layer": "building",
          filter: ["!=", ["to-string", ["get", "ftCode"]], "3101", ["collator", { "case-sensitive": true }]],
          paint: { "fill-color": ["global-state", "buildingColor"], "fill-opacity": ["case", ["is-supported-script", ["get", "name"]], 0.8, 0.2] } },
        { id: "road", type: "line", source: "gsi", "source-layer": "road",
          paint: { "line-color": ["match", ["at", 0, ["split", ["to-string", ["get", "rdCtg"]], ""]], "0", "#e07040", "#777777"],
            "line-width": ["length", ["join", ["literal", ["a", "b"]], "--"]] } },
      ]),
      state: { buildingColor: { default: "#b48ccc" } },
    },
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
  // Lines beside their geometry (`line-offset`, per feature too), cased by a gap (`line-gap-width`)
  // and blurred (`line-blur`), through miter, bevel and round joins.
  "line-offset": {
    style: style([
      { id: "road", type: "line", source: "gsi", "source-layer": "road", layout: { "line-join": "round", "line-cap": "round" },
        paint: { "line-color": "#e8a33b", "line-width": 2, "line-offset": ["match", ["get", "rdCtg"], [0, 1], 6, -3] } },
      { id: "rail", type: "line", source: "gsi", "source-layer": "railway", layout: { "line-join": "miter" },
        paint: { "line-color": "#555555", "line-width": 1.5, "line-offset": 4 } },
      { id: "river", type: "line", source: "gsi", "source-layer": "river", layout: { "line-join": "bevel" },
        paint: { "line-color": "#3a7bd5", "line-width": 1, "line-offset": -2.5 } },
    ]),
    camera: TOKYO,
    limits: { mean: 0.05, p99: 1 },
  },
  "line-gap": {
    style: style([
      { id: "road", type: "line", source: "gsi", "source-layer": "road", layout: { "line-join": "round", "line-cap": "round" },
        paint: { "line-color": "#8a6d4b", "line-width": 1.5, "line-gap-width": ["match", ["get", "rdCtg"], [0, 1], 8, 4] } },
      { id: "rail", type: "line", source: "gsi", "source-layer": "railway",
        paint: { "line-color": "#333333", "line-width": 3, "line-blur": 2, "line-opacity": 0.8 } },
    ]),
    camera: { center: [139.7671, 35.6812], zoom: 15.6, bearing: 25, pitch: 0 },
    limits: { mean: 0.05, p99: 1 },
  },
  // Every layer kind's `*-translate`, anchored to the map or to the turned viewport.
  translate: {
    style: style([
      { id: "water", type: "fill", source: "gsi", "source-layer": "waterarea", paint: { "fill-color": "#a8d4f0", "fill-translate": [12, -6] } },
      { id: "building", type: "fill", source: "gsi", "source-layer": "building",
        paint: { "fill-color": "#d9c9b6", "fill-translate": [-4, 5], "fill-translate-anchor": "viewport" } },
      { id: "road", type: "line", source: "gsi", "source-layer": "road",
        paint: { "line-color": "#999999", "line-width": 2, "line-translate": [6, 6], "line-translate-anchor": "viewport" } },
      { id: "pt", type: "circle", source: "gsi", "source-layer": "symbol",
        paint: { "circle-radius": 4, "circle-color": "#3b6ed6", "circle-translate": [0, -10] } },
    ]),
    camera: { center: [139.7671, 35.6812], zoom: 15, bearing: -35, pitch: 0 },
    limits: { mean: 0.05, p99: 1 },
  },
  // Circles under pitch: on the map or facing the viewer, growing with the map or kept on screen,
  // blurred.
  "circle-pitch": {
    style: style([
      { id: "map-map", type: "circle", source: "gsi", "source-layer": "symbol", filter: ["==", ["%", ["get", "ftCode"], 4], 0],
        paint: { "circle-radius": 6, "circle-color": "#d7191c", "circle-pitch-alignment": "map" } },
      { id: "map-viewport", type: "circle", source: "gsi", "source-layer": "symbol", filter: ["==", ["%", ["get", "ftCode"], 4], 1],
        paint: { "circle-radius": 6, "circle-color": "#2b83ba", "circle-pitch-alignment": "map", "circle-pitch-scale": "viewport" } },
      { id: "viewport-viewport", type: "circle", source: "gsi", "source-layer": "symbol", filter: ["==", ["%", ["get", "ftCode"], 4], 2],
        paint: { "circle-radius": 6, "circle-color": "#1a9641", "circle-pitch-scale": "viewport", "circle-stroke-width": 1.5, "circle-stroke-color": "#ffffff" } },
      { id: "blurred", type: "circle", source: "gsi", "source-layer": "symbol", filter: ["==", ["%", ["get", "ftCode"], 4], 3],
        paint: { "circle-radius": 8, "circle-color": "#7a4fb0", "circle-blur": 0.6 } },
    ]),
    camera: { center: [139.7671, 35.6812], zoom: 15.2, bearing: 20, pitch: 55 },
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
  // Icons from a sprite (MapLibre's symbol_icon, and symbol_sdf for SDF icons with halos): at
  // size 1 sampled as they are, then turned, scaled and pitched with the map, then at 2x.
  icons: {
    style: ICONS(),
    camera: { center: [139.7671, 35.6812], zoom: 15.3, bearing: 0, pitch: 0 },
    limits: { mean: 0.05, p99: 1 },
  },
  "icons-turned": {
    style: ICONS({ "icon-rotate": 25, "icon-size": 1.4, "icon-rotation-alignment": "map" }),
    camera: { center: [139.7671, 35.6812], zoom: 15.4, bearing: 30, pitch: 40 },
    limits: { mean: 0.05, p99: 1 },
  },
  // Icons along GSI contours, turned to the line (pins) or upright on it (SDF rings), then tilted.
  "icons-lines": {
    style: LINE_ICONS,
    camera: { center: [139.702, 35.664], zoom: 14.7, bearing: 40, pitch: 0 },
    limits: { mean: 0.05, p99: 1 },
  },
  "icons-lines-tilted": {
    style: LINE_ICONS,
    camera: { center: [139.702, 35.664], zoom: 14.6, bearing: -15, pitch: 45 },
    limits: { mean: 0.05, p99: 1 },
  },
  "icons-2x": {
    style: ICONS({ "icon-pitch-alignment": "viewport", "icon-rotation-alignment": "map" }),
    camera: { center: [139.7671, 35.6812], zoom: 15.6, bearing: -20, pitch: 0 },
    dpr: 2,
    limits: { mean: 0.05, p99: 1 },
  },
  // Text (MapLibre's symbol_sdf): a wide blurred halo in a pass of its own; a thin one with the
  // text, translucent, spaced, turned and moved; format sections' colors and fonts; along lines
  // (where glyphs lie as MapLibre's, so the halo and its blur are compared); on a 2x screen.
  text: {
    style: TEXT(),
    camera: { center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 },
    limits: { mean: 3.4, p99: 80 },
    gap: "point text lies about 0.5 px up and left of MapLibre's (glyph layout of worker/js/text.mjs)",
  },
  "text-thin-halo": {
    style: TEXT({ "text-letter-spacing": 0.1, "text-rotate": ["match", ["get", "annoCtg"], 412, 20, -10], "text-transform": "uppercase" },
      { "text-halo-width": 0.8, "text-halo-blur": 0.5, "text-opacity": 0.7, "text-translate": [6, -4] }),
    camera: { center: [139.7645, 35.6795], zoom: 15.4, bearing: 30, pitch: 0 },
    limits: { mean: 1.2, p99: 45 },
    gap: "point text lies about 0.5 px up and left of MapLibre's (glyph layout of worker/js/text.mjs)",
  },
  "text-format": {
    style: TEXT({ "text-field": ["format", ["get", "knj"], { "text-color": "#c1121f", "text-font": ["literal", ["Noto Sans Regular"]] }, "\n", {}, "St", { "font-scale": 0.8 }] },
      { "text-halo-width": 1, "text-halo-blur": 0 }),
    camera: { center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 },
    limits: { mean: 2.0, p99: 64 },
    gap: "point text lies about 0.5 px up and left of MapLibre's (glyph layout of worker/js/text.mjs)",
  },
  "text-lines": {
    style: style([{ id: "c", type: "symbol", source: "gsi", "source-layer": "contour",
      layout: { "symbol-placement": "line", "text-field": "{alti}m", "text-font": ["Noto Sans Italic"], "text-size": 12, "text-letter-spacing": 0.2 },
      paint: { "text-color": "#8a6d3b", "text-halo-color": "#fffbe6", "text-halo-width": 2, "text-halo-blur": 1.5 } }]),
    camera: { center: [139.702, 35.664], zoom: 14.6, bearing: -15, pitch: 45 },
    limits: { mean: 0.05, p99: 1 },
  },
  "text-2x": {
    style: TEXT({}, { "text-halo-width": 1, "text-halo-blur": 0.8 }),
    camera: { center: [139.7671, 35.6812], zoom: 15.3, bearing: 0, pitch: 0 },
    dpr: 2,
    limits: { mean: 3.1, p99: 112 },
    gap: "point text lies about 0.5 px up and left of MapLibre's (glyph layout of worker/js/text.mjs)",
  },
  // Patterns from a sprite (MapLibre's fill_pattern, fill_outline_pattern, background_pattern):
  // a constant and a per-feature pattern, an outline in the pattern and one in a color, a
  // translucent background; then the @2x sheet on a 2x screen at a fractional zoom.
  patterns: {
    style: patterned(PATTERN_LAYERS),
    camera: TOKYO,
    limits: { mean: 0.08, p99: 2 },
    gap: "translucent patterns: 1-2 levels of rounding, and edge pixels where antialiased outlines meet",
  },
  "patterns-2x": {
    style: patterned(PATTERN_LAYERS),
    camera: { center: [139.7671, 35.6812], zoom: 15.6, bearing: 0, pitch: 0 },
    dpr: 2,
    limits: { mean: 0.08, p99: 2 },
    gap: "translucent patterns: 1-2 levels of rounding, and edge pixels where antialiased outlines meet",
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
  // Image sources (MapLibre's ImageSource and raster draw): a rectangle reaching past its tile, a
  // trapezoid warped projectively and a strongly foreshortened one blended over a grid, with paint.
  images: {
    style: IMAGES,
    camera: { center: [139.767, 35.677], zoom: 13.6, bearing: 0, pitch: 0 },
    limits: { mean: 0.05, p99: 1 },
  },
  "images-turned": {
    style: IMAGES,
    camera: { center: [139.767, 35.677], zoom: 13.9, bearing: -25, pitch: 50 },
    limits: { mean: 0.05, p99: 1 },
  },
  // Line and extrusion patterns (MapLibre's line_pattern and fill_extrusion_pattern): images as
  // tall as the line, along its distance; walls by their distance and height, roofs by tile units.
  "line-patterns": {
    style: {
      ...style([
        { id: "road", type: "line", source: "gsi", "source-layer": "road", layout: { "line-cap": "round", "line-join": "round" },
          paint: { "line-pattern": "dots", "line-width": ["interpolate", ["linear"], ["zoom"], 15, 4, 17, 12] } },
        { id: "rail", type: "line", source: "gsi", "source-layer": "railway", paint: { "line-pattern": "stripes", "line-width": 6, "line-opacity": 0.8 } },
      ]),
      sprite: SPRITE,
    },
    camera: { center: [139.7671, 35.6812], zoom: 16.3, bearing: 0, pitch: 0 },
    limits: { mean: 0.2, p99: 1 },
    gap: "pattern edges shift by under a pixel along the line",
  },
  "extrusion-patterns": {
    style: {
      ...style([
        { id: "building-3d", type: "fill-extrusion", source: "gsi", "source-layer": "building",
          paint: {
            "fill-extrusion-pattern": ["match", ["get", "ftCode"], 3103, "checker", "odd"],
            "fill-extrusion-height": ["match", ["get", "ftCode"], 3103, 40, 12],
            "fill-extrusion-opacity": 0.9,
          } },
      ]),
      sprite: SPRITE,
    },
    camera: { center: [139.7671, 35.6812], zoom: 16, bearing: 30, pitch: 50 },
    limits: { mean: 0.2, p99: 1 },
  },

  // Translucent extrusions: each pixel colored once by its nearest surface, coincident roofs too
  // (MapLibre's depth pass, then a color pass counted by the stencil).
  "extrusions-translucent": {
    style: style([{ id: "building-3d", type: "fill-extrusion", source: "gsi", "source-layer": "building",
      paint: { "fill-extrusion-color": "#1e8c46", "fill-extrusion-height": ["match", ["get", "ftCode"], 3103, 40, 12], "fill-extrusion-opacity": 0.9 } }]),
    camera: { center: [139.7671, 35.6812], zoom: 15.5, bearing: 30, pitch: 50 },
    limits: { mean: 0.12, p99: 1 },
  },
  "hillshade-standard": {
    style: hillshade({ "hillshade-exaggeration": 0.7, "hillshade-shadow-color": "#473b24", "hillshade-accent-color": "#5a4a2a" }),
    camera: FUJI,
    limits: { mean: 0.05, p99: 1 },
  },
  "hillshade-basic": {
    style: hillshade({ "hillshade-method": "basic", "hillshade-illumination-altitude": 35, "hillshade-highlight-color": "rgba(255, 250, 230, 0.8)" }),
    camera: FUJI,
    limits: { mean: 0.05, p99: 1 },
  },
  "hillshade-combined": {
    style: hillshade({ "hillshade-method": "combined", "hillshade-exaggeration": 0.8, "hillshade-illumination-direction": 300 }),
    camera: FUJI,
    limits: { mean: 0.05, p99: 1 },
  },
  "hillshade-igor": {
    style: hillshade({ "hillshade-method": "igor", "hillshade-illumination-anchor": "map", "hillshade-shadow-color": "#2a3a5a" }),
    camera: FUJI,
    limits: { mean: 0.05, p99: 1 },
  },
  // Four lights, colors and altitudes per light (a list shorter than the colors repeats its last).
  "hillshade-multidirectional": {
    style: hillshade({
      "hillshade-method": "multidirectional",
      "hillshade-illumination-direction": [270, 315, 0, 45],
      "hillshade-illumination-altitude": [30, 30, 45],
      "hillshade-highlight-color": ["#ffeedd", "#ffffff", "#ddeeff", "#ffffff"],
      "hillshade-shadow-color": ["#552200", "#000000", "#002255", "#000000"],
    }),
    camera: FUJI,
    limits: { mean: 0.05, p99: 1 },
  },
  // The light anchored to the viewport turns with the map; slopes sampled nearest.
  "hillshade-turned": {
    style: hillshade({ "hillshade-method": "basic", resampling: "nearest" }),
    camera: { ...FUJI, bearing: 40 },
    limits: { mean: 0.05, p99: 1 },
  },
  // Color relief (MapLibre's color_relief): a ramp over elevation with a translucent top stop, under
  // a hillshade; then sampled nearest at its opacity.
  "color-relief": {
    style: dem([
      { id: "relief", type: "color-relief", source: "dem", paint: { "color-relief-color": RELIEF } },
      { id: "hillshade", type: "hillshade", source: "dem", paint: { "hillshade-method": "igor" } },
    ]),
    camera: FUJI,
    limits: { mean: 0.05, p99: 1 },
  },
  "color-relief-nearest": {
    style: dem([{ id: "relief", type: "color-relief", source: "dem", paint: { "color-relief-color": RELIEF, "color-relief-opacity": 0.7, resampling: "nearest" } }]),
    camera: { ...FUJI, zoom: 11.95, bearing: -20 },
    limits: { mean: 0.05, p99: 1 },
  },
};
