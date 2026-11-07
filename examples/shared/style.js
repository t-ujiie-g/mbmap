// The showcase's style: GSI's vector tiles and DEM, the places and the stations (clustered and
// as a heatmap) as GeoJSON, and in 3D terrain, sky and extruded buildings; `?local=1` reads the bench fixtures
// (z14 around Tokyo Station) instead of GSI's servers.
import { GSI_LAYERS } from "./layers.js";
import { PLACES } from "./places.js";
import { STATIONS_HEAT_SOURCE, STATIONS_SOURCE, stationHeatLayer, stationLayers } from "./stations.js";

// Tokyo Station, Yurakucho, the Imperial Palace, Kanda, Nihonbashi and back.
const WALK = {
  type: "Feature", properties: {},
  geometry: { type: "LineString", coordinates: [
    [139.7671, 35.6812], [139.7631, 35.6751], [139.7528, 35.6852], [139.7708, 35.6918], [139.7745, 35.684], [139.7671, 35.6812],
  ] },
};

const GSI = "https://cyberjapandata.gsi.go.jp/xyz";
const local = new URLSearchParams(location.search).get("local") === "1";
// Relative to the page (examples/<name>/): a bundle's import.meta.url lies elsewhere.
const fixtures = new URL("../../bench/fixtures/", location.href).href;
// The showcase's own sprite (a hatch for structures, a station icon), at 1x and 2x.
const SPRITE = new URL("../shared/sprite/sprite", location.href).href;
const HATCH = { id: "structurea-hatch", type: "fill", source: "gsi", "source-layer": "structurea", paint: { "fill-pattern": "hatch" } };

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

// Each contour's height written along it, turned to read upright.
const CONTOUR_LABELS = {
  id: "contour-label", type: "symbol", source: "gsi", "source-layer": "contour",
  layout: { "symbol-placement": "line", "symbol-spacing": 300, "text-field": "{alti}", "text-size": 10 },
  paint: { "text-color": "#8a6d3b", "text-halo-color": "#ffffff", "text-halo-width": 1 },
};

// Spot heights grow with the square root of their height (GSI writes some as strings).
const ELEVATION_RADIUS = ["+", 2, ["*", ["sqrt", ["max", ["to-number", ["get", "alti"], 0], 0]], 0.3]];

/** Layers the panel shows and hides together, by the name of each group. */
export const LAYER_GROUPS = [
  { name: "陰影", ids: ["hillshade"] },
  { name: "等高線", ids: ["contour", "contour-label", "elevation"] },
  { name: "建物", ids: ["building", "building-outline", "building-3d"] },
  { name: "道路・鉄道", ids: ["road-casing", "road", "railway"] },
  { name: "注記", ids: ["symbol", "label", "label-vertical"] },
  { name: "地点", ids: ["places", "places-label"] },
  { name: "駅の密度", ids: ["stations-heat"] },
  { name: "山手線の駅", ids: ["stations-cluster", "stations", "stations-count"] },
  { name: "散歩道", ids: ["walk"] },
  { name: "駅の略図", ids: ["sketch"] },
];

/** The groups off at first: the map opens plain, and the panel turns these on. */
export const HIDDEN_AT_START = new Set(["駅の密度", "散歩道", "駅の略図"]);

/** The datasets read with mbmap/data by id, as `{ name, data }`: overlays that every new style keeps. */
export const datasets = new Map();

/** The raster overlays of Web services (services.js) by id, as `{ name, source }`: kept by every new style too. */
export const serviceLayers = new Map();

/** The first vector overlay of `layers` (a style's), which raster overlays go under. */
export const firstVectorOverlay = (layers) => layers.find((l) => l.metadata?.["mbmap:overlay"] && !serviceLayers.has(l.id))?.id;

/** A service overlay's layer. */
export const serviceLayer = (id) => ({ id, type: "raster", source: id, metadata: { "mbmap:overlay": true }, paint: { "raster-opacity": 0.85 } });

/** A tile URL as the showcase reads it: GSI's pale map from the fixtures' standard map with `?local=1`. */
export const tileUrl = (url) => (local ? url.replace(`${GSI}/pale/`, `${fixtures}gsi-std/`) : url);

/** The basemaps (`createStyle`'s `basemap`): GSI's vector map, or its aerial photos with labels. */
export const BASEMAPS = [
  { id: "map", title: "地図" },
  { id: "photo", title: "写真" },
];

/** What the legend calls each layer. */
export const LAYER_TITLES = {
  waterarea: "水域", structurea: "構造物", "structurea-hatch": "構造物の斜線", building: "建物", "building-3d": "建物（3D）", "building-outline": "建物の輪郭",
  contour: "等高線", "contour-label": "等高線の高さ", river: "河川", "road-casing": "道路の縁", road: "道路", railway: "鉄道", boundary: "境界",
  elevation: "標高点", symbol: "記号", label: "注記", "label-vertical": "注記（縦書き）", places: "地点", "places-label": "地点名",
  "stations-cluster": "駅のまとまり", stations: "山手線の駅", "stations-count": "駅の数", "stations-heat": "駅の密度", walk: "散歩道",
  hillshade: "陰影", photo: "写真", sketch: "駅の略図",
};

// GSI's road classes (rdCtg).
const ROAD_CLASSES = { 0: "国道", 1: "都道府県道", 2: "市区町村道", 3: "高速道路" };

/** A legend item's label: GSI's road classes by name, other codes as they are, or "その他". */
export function legendLabel(layer, category) {
  if (category.other) return "その他";
  if (category.values) return category.values.map((v) => (layer.id === "road" || layer.id === "road-casing" ? ROAD_CLASSES[v] ?? v : v)).join("・");
  return undefined;
}

/** The GeoJSON source of a dataset. */
export const datasetSource = (data) => ({ type: "geojson", data });

/** A dataset's layers: its polygons, lines and points, kept apart by geometry. */
export function datasetLayers(id) {
  const metadata = { "mbmap:overlay": true };
  const only = (...types) => ["in", ["geometry-type"], ["literal", types]];
  return [
    { id: `${id}-fill`, type: "fill", source: id, metadata, filter: only("Polygon", "MultiPolygon"), paint: { "fill-color": "#2f5bd0", "fill-opacity": 0.2 } },
    { id: `${id}-line`, type: "line", source: id, metadata, filter: only("LineString", "MultiLineString", "Polygon", "MultiPolygon"), paint: { "line-color": "#2f5bd0", "line-width": 2 } },
    { id: `${id}-point`, type: "circle", source: id, metadata, filter: only("Point", "MultiPoint"), paint: { "circle-radius": 6, "circle-color": "#2f5bd0", "circle-stroke-color": "#ffffff", "circle-stroke-width": 2 } },
  ];
}

/** The ids of the layers in the groups named in `hidden`. */
export function hiddenLayers(hidden) {
  return new Set(LAYER_GROUPS.filter((g) => hidden.has(g.name)).flatMap((g) => g.ids));
}

/** `places` with a marker named `name` added at `center`, for `getSource("places").setData`. */
export function withMarker(places, center, name) {
  const marker = { type: "Feature", properties: { name }, geometry: { type: "Point", coordinates: [center.lng, center.lat] } };
  return { ...places, features: [...places.features, marker] };
}

/** The DEM tiles the style draws (GSI's, or the fixtures with `?local=1`): the profile samples them too. */
export const DEM_TILES = local ? `${fixtures}gsi-dem/{z}/{x}/{y}.png` : `${GSI}/dem_png/{z}/{x}/{y}.png`;

/**
 * "2d" or "3d" over `basemap` ("map" or "photo") as a MapLibre style object, without the layer groups
 * named in `hidden`; the places are overlays, kept when the basemap changes.
 */
export function createStyle(mode, hidden = HIDDEN_AT_START, places = PLACES, basemap = "map") {
  const sources = {
    gsi: local
      ? { type: "vector", tiles: [`${fixtures}gsi-bvmap/{z}/{x}/{y}.pbf`], minzoom: 14, maxzoom: 14 }
      : { type: "vector", tiles: [`${GSI}/experimental_bvmap/{z}/{x}/{y}.pbf`], minzoom: 4, maxzoom: 16 },
    dem: local
      ? { type: "raster-dem", tiles: [DEM_TILES], tileSize: 256, minzoom: 14, maxzoom: 14, encoding: "gsi" }
      : { type: "raster-dem", tiles: [DEM_TILES], tileSize: 256, minzoom: 1, maxzoom: 14, encoding: "gsi" },
    places: { type: "geojson", data: places, promoteId: "name" },
    stations: STATIONS_SOURCE,
    "stations-heat": STATIONS_HEAT_SOURCE,
    // A walk around Tokyo Station; line metrics give its gradient from start to finish.
    walk: { type: "geojson", lineMetrics: true, data: WALK },
    // A self-made sketch of the station yard, an image placed by its corners along the tracks.
    sketch: {
      type: "image", url: new URL("../shared/station-sketch.png", location.href).href,
      coordinates: [[139.76263, 35.67878], [139.76536, 35.6849], [139.77097, 35.68322], [139.76824, 35.6771]],
    },
    // GSI's seamless aerial photos (the standard map's images with ?local=1: the bench fixtures).
    photo: local
      ? { type: "raster", tiles: [`${fixtures}gsi-std/{z}/{x}/{y}.png`], tileSize: 256, minzoom: 14, maxzoom: 14 }
      : { type: "raster", tiles: [`${GSI}/seamlessphoto/{z}/{x}/{y}.jpg`], tileSize: 256, minzoom: 2, maxzoom: 18 },
  };
  sources.photo.attribution = "国土地理院 全国最新写真（シームレス）";
  sources.gsi.attribution = "国土地理院ベクトルタイル提供実験";
  sources.dem.attribution = "国土地理院 標高タイル";
  const overlay = { "mbmap:overlay": true };
  const base =
    basemap === "photo"
      ? [{ id: "photo", type: "raster", source: "photo" }, ...GSI_LAYERS.filter((l) => l.id.startsWith("label"))]
      : [
          { id: "hillshade", type: "hillshade", source: "dem", paint: { "hillshade-exaggeration": 0.5, "hillshade-shadow-color": "#5a4a35" } },
          ...GSI_LAYERS.flatMap((l) => {
            if (l.id === "elevation") return [{ ...l, paint: { ...l.paint, "circle-radius": ELEVATION_RADIUS } }];
            if (l.id === "structurea") return [l, HATCH];
            if (l.id === "contour") return [l, CONTOUR_LABELS];
            if (mode !== "3d") return [l];
            if (l.id === "building-outline") return [];
            return l.id === "building" ? [BUILDINGS_3D] : [l];
          }),
        ];
  const layers = [
    { id: "background", type: "background", paint: { "background-color": "#f5f3ee" } },
    ...base,
    { id: "sketch", type: "raster", source: "sketch", metadata: overlay, paint: { "raster-opacity": 0.55 } },
    stationHeatLayer(overlay),
    ...stationLayers(overlay),
    {
      id: "walk", type: "line", source: "walk", metadata: overlay,
      layout: { "line-cap": "round", "line-join": "round" },
      paint: {
        "line-width": ["interpolate", ["linear"], ["zoom"], 12, 3, 16, 8],
        "line-gradient": ["interpolate", ["linear"], ["line-progress"], 0, "#1a9850", 0.5, "#fee08b", 1, "#d73027"],
      },
    },
    {
      id: "places", type: "circle", source: "places", metadata: overlay,
      paint: {
        "circle-radius": ["case", ["boolean", ["feature-state", "hover"], false], 10, 6],
        "circle-color": [
          "case",
          ["boolean", ["feature-state", "selected"], false], "#2166ac",
          ["boolean", ["feature-state", "hover"], false], "#b2182b",
          "#d6604d",
        ],
        "circle-stroke-width": ["case", ["boolean", ["feature-state", "selected"], false], 4, 2],
        "circle-stroke-color": "#ffffff",
      },
    },
    {
      id: "places-label", type: "symbol", source: "places", metadata: overlay,
      // Beside the dot: below it, or else above, right or left, whichever is free.
      layout: {
        "text-field": "{name}", "text-size": 14, "symbol-sort-key": 0,
        "text-variable-anchor": ["top", "bottom", "left", "right"], "text-radial-offset": 0.8, "text-justify": "auto",
      },
      paint: { "text-color": "#8c2d1f", "text-halo-color": "#ffffff", "text-halo-width": 2 },
    },
  ];
  // Raster overlays go under the vector ones (places, stations, datasets).
  const under = layers.findIndex((l) => l.metadata?.["mbmap:overlay"]);
  for (const [id, { source }] of serviceLayers) sources[id] = source;
  layers.splice(under < 0 ? layers.length : under, 0, ...[...serviceLayers.keys()].map(serviceLayer));
  for (const [id, { data }] of datasets) {
    sources[id] = datasetSource(data);
    layers.push(...datasetLayers(id));
  }
  const off = hiddenLayers(hidden);
  for (const [i, l] of layers.entries()) {
    if (off.has(l.id)) layers[i] = { ...l, layout: { ...l.layout, visibility: "none" } };
  }
  const style = { version: 8, name: `mbmap showcase (${mode})`, sprite: SPRITE, sources, layers };
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
