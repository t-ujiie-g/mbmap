// Stations read from a CSV and an area from WKT by mbmap/data, drawn as GeoJSON
// sources and counted in mbmap/analysis from the same tables.
import { Map } from "mbmap";
import { load } from "mbmap/analysis";
import { parse, read } from "mbmap/data";

const stations = await read("./stations.csv");
const area = await parse("SRID=4326;POLYGON ((139.760 35.670, 139.775 35.670, 139.775 35.688, 139.760 35.688, 139.760 35.670))", { format: "wkt" });
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
    },
    layers: [
      { id: "background", type: "background", paint: { "background-color": "#f5f3ee" } },
      { id: "road", type: "line", source: "gsi", "source-layer": "road", paint: { "line-color": "#ffffff", "line-width": 2 } },
      { id: "area", type: "fill", source: "area", paint: { "fill-color": "#3b82f6", "fill-opacity": 0.2 } },
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
  };
  window.__loaded = performance.now();
});
window.__map = map;
