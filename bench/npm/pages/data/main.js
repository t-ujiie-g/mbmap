// Stations read from a CSV, an area from WKT and lines from TopoJSON by mbmap/data,
// drawn as GeoJSON sources and counted in mbmap/analysis from the same tables. The
// shapefiles (bench/data/pack-fixtures.mjs writes them) are read by the pack test.
import { Map } from "mbmap";
import { load } from "mbmap/analysis";
import { parse, read } from "mbmap/data";

const stations = await read("./stations.csv");
const area = await parse("SRID=4326;POLYGON ((139.760 35.670, 139.775 35.670, 139.775 35.688, 139.760 35.688, 139.760 35.670))", { format: "wkt" });
const lines = await read("./lines.topojson");
const [points, polygons] = await Promise.all([load(stations), load(area)]);
const inside = await points.pointsWithin(polygons);

const map = new Map({
  container: "map",
  center: [139.767, 35.684],
  zoom: 14,
  style: {
    version: 8,
    sources: {
      gsi: { type: "vector", tiles: ["/bench/fixtures/gsi-bvmap/{z}/{x}/{y}.pbf"], minzoom: 14, maxzoom: 14, attribution: "国土地理院ベクトルタイル提供実験" },
      area: { type: "geojson", data: area.toGeoJSON() },
      stations: { type: "geojson", data: stations.toGeoJSON() },
      lines: { type: "geojson", data: lines.toGeoJSON() },
    },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#f5f3ee" } },
      { id: "road", type: "line", source: "gsi", "source-layer": "road", paint: { "line-color": "#ffffff", "line-width": 2 } },
      { id: "area", type: "fill", source: "area", paint: { "fill-color": "#3b82f6", "fill-opacity": 0.2 } },
      { id: "lines", type: "line", source: "lines", paint: { "line-color": "#16a34a", "line-width": 3 } },
      { id: "stations", type: "circle", source: "stations", paint: { "circle-radius": 6, "circle-color": "#e4572e" } },
    ],
  },
});
map.on("error", (e) => console.error(e.error));
map.once("load").then(() => {
  window.__data = {
    length: stations.length,
    columns: stations.columns,
    features: stations.toGeoJSON().features,
    area: area.toGeoJSON().features[0].geometry.type,
    datasets: [points.length, polygons.length],
    inside: Array.from(inside),
    lines: { layer: lines.layer, layers: lines.layers, features: lines.toGeoJSON().features },
  };
  window.__loaded = performance.now();
});
window.__map = map;
