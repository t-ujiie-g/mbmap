// A shape being drawn, as drawing tools draw it: a GeoJSON source updated with
// setData as one vertex moves. Per update, the time until the map is idle again
// (?engine=mbmap through the npm facade, or maplibre), over the bench base map.
const params = new URLSearchParams(location.search);
const engine = params.get("engine");
const CENTER = [139.7671, 35.6812];
const styleText = (await (await fetch("/bench/maplibre/style.json")).text()).replaceAll("{origin}", location.origin);
const style = JSON.parse(styleText);
style.sources.draw = { type: "geojson", data: { type: "FeatureCollection", features: [] } };
style.layers.push(
  { id: "draw-fill", type: "fill", source: "draw", filter: ["==", ["geometry-type"], "Polygon"], paint: { "fill-color": "#e4572e", "fill-opacity": 0.2 } },
  { id: "draw-line", type: "line", source: "draw", paint: { "line-color": "#e4572e", "line-width": 2 } },
  { id: "draw-vertex", type: "circle", source: "draw", filter: ["==", ["geometry-type"], "Point"], paint: { "circle-radius": 4, "circle-color": "#fff", "circle-stroke-color": "#e4572e", "circle-stroke-width": 2 } },
);

const lib = engine === "maplibre" ? await import("/bench/node_modules/maplibre-gl/dist/maplibre-gl.mjs") : await import("/npm/dist/index.js");
const map = new lib.Map({ container: "map", style, center: CENTER, zoom: 15, attributionControl: false, ...(engine === "maplibre" ? { fadeDuration: 0 } : {}) });
// idle can come in the same task as load.
await new Promise((r) => map.once("idle", r));

/** A ring of `n` vertices about 400 m across, vertex 0 moved by `t`, with a point per vertex. */
function shape(n, t) {
  const ring = [];
  for (let i = 0; i < n; i++) {
    const a = (2 * Math.PI * i) / n;
    const r = i === 0 ? 0.004 + 0.001 * Math.sin(t) : 0.004;
    ring.push([CENTER[0] + r * Math.cos(a) * 1.2, CENTER[1] + r * Math.sin(a)]);
  }
  ring.push(ring[0]);
  const points = ring.slice(0, Math.min(n, 1000)).map((c) => ({ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: c } }));
  return { type: "FeatureCollection", features: [{ type: "Feature", properties: {}, geometry: { type: "Polygon", coordinates: [ring] } }, ...points] };
}

const quantile = (xs, p) => [...xs].sort((a, b) => a - b)[Math.min(xs.length - 1, Math.floor(p * xs.length))];
const results = [];
for (const n of [10, 100, 1000, 5000]) {
  const times = [];
  for (let i = 0; i < 41; i++) {
    const data = shape(n, i);
    const idle = new Promise((r) => map.once("idle", r));
    const t0 = performance.now();
    map.getSource("draw").setData(data);
    await idle;
    if (i > 0) times.push(performance.now() - t0);
  }
  results.push({ vertices: n, median: quantile(times, 0.5), p95: quantile(times, 0.95) });
}
window.__results = results;
