// Seeded points counted per block in the analysis worker; the counts then
// color the blocks on the map. Nothing of the analysis runs on the main thread.
import { Map } from "mbmap";
import { load } from "mbmap/analysis";

let s = 7;
const rand = () => (s = (Math.imul(s, 1103515245) + 12345) >>> 0) / 4294967296;
const [x0, y0, size] = [139.7590, 35.6770, 0.0035];
const blocks = [];
for (let row = 0; row < 2; row++) {
  for (let col = 0; col < 3; col++) {
    const x = x0 + col * size;
    const y = y0 + row * size;
    const ring = [[x, y], [x + size * 0.9, y], [x + size * 0.9, y + size * 0.9], [x, y + size * 0.9], [x, y]];
    blocks.push({ type: "Feature", properties: { name: `${"ABC"[col]}${row + 1}` }, geometry: { type: "Polygon", coordinates: [ring] } });
  }
}
const points = Array.from({ length: 400 }, () => ({
  type: "Feature",
  properties: { v: Math.round(rand() * 100) },
  geometry: { type: "Point", coordinates: [x0 + rand() * size * 3, y0 + rand() * size * 2] },
}));

const polygons = await load({ type: "FeatureCollection", features: blocks });
const dots = await load({ type: "FeatureCollection", features: points });
const [areas, counts, inside] = await Promise.all([polygons.areas(), polygons.collect(dots, "v"), dots.pointsWithin(polygons)]);

const rows = document.querySelector("tbody");
blocks.forEach((b, i) => {
  b.properties.count = counts.count[i];
  const tr = rows.insertRow();
  for (const v of [b.properties.name, Math.round(areas[i]).toLocaleString(), counts.count[i], counts.mean[i].toFixed(1)]) tr.insertCell().textContent = v;
});
// The blocks grown by 30 m on the ground and merged: geometry.wasm, loaded now.
const zone = await (await polygons.buffer(30)).dissolve();
const zoneGeoJSON = await zone.toGeoJSON();
const within = new Set(inside);
points.forEach((p, i) => (p.properties.inside = within.has(i)));

const map = new Map({
  container: "map",
  center: [139.7642, 35.6805],
  zoom: 15.5,
  style: {
    version: 8,
    sources: {
      gsi: { type: "vector", tiles: ["/bench/fixtures/gsi-bvmap/{z}/{x}/{y}.pbf"], minzoom: 14, maxzoom: 14, attribution: "国土地理院ベクトルタイル提供実験" },
      zone: { type: "geojson", data: zoneGeoJSON },
      blocks: { type: "geojson", data: { type: "FeatureCollection", features: blocks } },
      points: { type: "geojson", data: { type: "FeatureCollection", features: points } },
    },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#f5f3ee" } },
      { id: "building", type: "fill", source: "gsi", "source-layer": "building", paint: { "fill-color": "#e3ddd3" } },
      { id: "road", type: "line", source: "gsi", "source-layer": "road", paint: { "line-color": "#ffffff", "line-width": 2 } },
      { id: "zone", type: "fill", source: "zone", paint: { "fill-color": "#3b82f6", "fill-opacity": 0.15 } },
      { id: "zone-edge", type: "line", source: "zone", paint: { "line-color": "#3b82f6", "line-width": 1.5 } },
      {
        id: "blocks", type: "fill", source: "blocks",
        paint: { "fill-color": ["interpolate", ["linear"], ["get", "count"], 40, "#fde0c5", 90, "#e4572e"], "fill-opacity": 0.7 },
      },
      {
        id: "points", type: "circle", source: "points",
        paint: { "circle-radius": 3, "circle-color": ["case", ["get", "inside"], "#1f4e79", "#999999"] },
      },
    ],
  },
});
map.on("error", (e) => console.error(e.error));
map.once("load").then(() => {
  window.__analysis = { areas: Array.from(areas), count: Array.from(counts.count), inside: inside.length };
  window.__loaded = performance.now();
});
window.__map = map;
