// The showcase's style: GSI's vector tiles and DEM, the places as GeoJSON, and
// in 3D terrain, sky and extruded buildings; `?local=1` reads the bench
// fixtures (z14 around Tokyo Station) instead of GSI's servers.
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

/** Layers the panel shows and hides together, by the name of each group; `DEFAULT_HIDDEN` start hidden. */
export const LAYER_GROUPS = [
  { name: "航空写真", ids: ["photo"] },
  { name: "陰影", ids: ["hillshade"] },
  { name: "等高線", ids: ["contour", "elevation"] },
  { name: "建物", ids: ["building", "building-outline", "building-3d"] },
  { name: "道路・鉄道", ids: ["road-casing", "road", "railway"] },
  { name: "注記", ids: ["symbol", "label", "label-vertical"] },
  { name: "地点", ids: ["places", "places-label"] },
];

export const DEFAULT_HIDDEN = ["航空写真"];

/** The ids of the layers in the groups named in `hidden`. */
export function hiddenLayers(hidden) {
  return new Set(LAYER_GROUPS.filter((g) => hidden.has(g.name)).flatMap((g) => g.ids));
}

/** `places` with a marker named `name` added at `center`, for `getSource("places").setData`. */
export function withMarker(places, center, name) {
  const marker = { type: "Feature", properties: { name }, geometry: { type: "Point", coordinates: [center.lng, center.lat] } };
  return { ...places, features: [...places.features, marker] };
}

/** "2d" or "3d" as a MapLibre style object, without the layer groups named in `hidden`. */
export function createStyle(mode, hidden = new Set(), places = PLACES) {
  const sources = {
    gsi: local
      ? { type: "vector", tiles: [`${fixtures}gsi-bvmap/{z}/{x}/{y}.pbf`], minzoom: 14, maxzoom: 14 }
      : { type: "vector", tiles: [`${GSI}/experimental_bvmap/{z}/{x}/{y}.pbf`], minzoom: 4, maxzoom: 16 },
    dem: local
      ? { type: "raster-dem", tiles: [`${fixtures}gsi-dem/{z}/{x}/{y}.png`], tileSize: 256, minzoom: 14, maxzoom: 14, encoding: "gsi" }
      : { type: "raster-dem", tiles: [`${GSI}/dem_png/{z}/{x}/{y}.png`], tileSize: 256, minzoom: 1, maxzoom: 14, encoding: "gsi" },
    places: { type: "geojson", data: places, promoteId: "name" },
    // GSI's seamless aerial photos (the standard map's images with ?local=1: the bench fixtures).
    photo: local
      ? { type: "raster", tiles: [`${fixtures}gsi-std/{z}/{x}/{y}.png`], tileSize: 256, minzoom: 14, maxzoom: 14 }
      : { type: "raster", tiles: [`${GSI}/seamlessphoto/{z}/{x}/{y}.jpg`], tileSize: 256, minzoom: 2, maxzoom: 18 },
  };
  sources.photo.attribution = "国土地理院 全国最新写真（シームレス）";
  sources.gsi.attribution = "国土地理院ベクトルタイル提供実験";
  sources.dem.attribution = "国土地理院 標高タイル";
  const layers = [
    { id: "background", type: "background", paint: { "background-color": "#f5f3ee" } },
    { id: "photo", type: "raster", source: "photo" },
    { id: "hillshade", type: "hillshade", source: "dem", paint: { "hillshade-exaggeration": 0.5, "hillshade-shadow-color": "#5a4a35" } },
    ...GSI_LAYERS.flatMap((l) => {
      if (mode !== "3d") return [l];
      if (l.id === "building-outline") return [];
      return l.id === "building" ? [BUILDINGS_3D] : [l];
    }),
    {
      id: "places", type: "circle", source: "places",
      paint: {
        "circle-radius": ["case", ["boolean", ["feature-state", "hover"], false], 10, 6],
        "circle-color": ["case", ["boolean", ["feature-state", "hover"], false], "#b2182b", "#d6604d"],
        "circle-stroke-width": 2,
        "circle-stroke-color": "#ffffff",
      },
    },
    {
      id: "places-label", type: "symbol", source: "places",
      layout: { "text-field": "{name}", "text-size": 14, "symbol-sort-key": 0 },
      paint: { "text-color": "#8c2d1f", "text-halo-color": "#ffffff", "text-halo-width": 2 },
    },
  ];
  const off = hiddenLayers(hidden);
  for (const [i, l] of layers.entries()) {
    if (off.has(l.id)) layers[i] = { ...l, layout: { ...l.layout, visibility: "none" } };
  }
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
