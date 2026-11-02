// The showcase's style: GSI's vector tiles and DEM, the places as a GeoJSON
// source, and in 3D the terrain, the sky and extruded buildings. Tiles come
// from GSI's servers, or from the bench fixtures with `?local=1` (the z14
// tiles around Tokyo Station, for tests without the network).
import { GSI_LAYERS } from "./layers.js";
import { PLACES } from "./places.js";

const GSI = "https://cyberjapandata.gsi.go.jp/xyz";
const local = new URLSearchParams(location.search).get("local") === "1";
const fixtures = new URL("../../bench/fixtures/", import.meta.url).href;

// GSI's buildings have no heights: 30 m for sturdy ones (ftCode 3103), 8 m for others.
const BUILDINGS_3D = {
  id: "building-3d", type: "fill-extrusion", source: "gsi", "source-layer": "building",
  filter: ["==", ["geometry-type"], "Polygon"],
  paint: {
    "fill-extrusion-color": ["match", ["get", "ftCode"], 3103, "#d9c9b6", "#e3ddd3"],
    "fill-extrusion-height": ["match", ["get", "ftCode"], 3103, 30, 8],
    "fill-extrusion-opacity": 0.9,
  },
};

/** "2d" or "3d" as a MapLibre style object. */
export function createStyle(mode) {
  const sources = {
    gsi: local
      ? { type: "vector", tiles: [`${fixtures}gsi-bvmap/{z}/{x}/{y}.pbf`], minzoom: 14, maxzoom: 14 }
      : { type: "vector", tiles: [`${GSI}/experimental_bvmap/{z}/{x}/{y}.pbf`], minzoom: 4, maxzoom: 16 },
    dem: local
      ? { type: "raster-dem", tiles: [`${fixtures}gsi-dem/{z}/{x}/{y}.png`], tileSize: 256, minzoom: 14, maxzoom: 14, encoding: "gsi" }
      : { type: "raster-dem", tiles: [`${GSI}/dem_png/{z}/{x}/{y}.png`], tileSize: 256, minzoom: 1, maxzoom: 14, encoding: "gsi" },
    places: { type: "geojson", data: PLACES },
  };
  sources.gsi.attribution = "国土地理院ベクトルタイル提供実験";
  sources.dem.attribution = "国土地理院 標高タイル";
  const layers = [
    { id: "background", type: "background", paint: { "background-color": "#f5f3ee" } },
    { id: "hillshade", type: "hillshade", source: "dem", paint: { "hillshade-exaggeration": 0.5, "hillshade-shadow-color": "#5a4a35" } },
    ...GSI_LAYERS.flatMap((l) => {
      if (mode !== "3d") return [l];
      if (l.id === "building-outline") return [];
      return l.id === "building" ? [BUILDINGS_3D] : [l];
    }),
    {
      id: "places", type: "circle", source: "places",
      paint: { "circle-radius": 6, "circle-color": "#d6604d", "circle-stroke-width": 2, "circle-stroke-color": "#ffffff" },
    },
    {
      id: "places-label", type: "symbol", source: "places",
      layout: { "text-field": "{name}", "text-size": 14, "symbol-sort-key": 0 },
      paint: { "text-color": "#8c2d1f", "text-halo-color": "#ffffff", "text-halo-width": 2 },
    },
  ];
  const style = { version: 8, name: `mbmap showcase (${mode})`, sources, layers };
  if (mode === "3d") {
    style.terrain = { source: "dem", exaggeration: 1.5 };
    style.sky = { "sky-color": "#88C6FC", "horizon-color": "#ffffff", "fog-color": "#ffffff" };
  }
  return style;
}

/** Where the camera goes for each mode: 3D tilts and turns. */
export function modeCamera(mode) {
  return mode === "3d" ? { pitch: 60, bearing: -20 } : { pitch: 0, bearing: 0 };
}
