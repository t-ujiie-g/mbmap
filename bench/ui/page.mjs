// mbmap with `mbmap/ui` controllers and MapLibre with its controls, one style and
// camera; bench/ui/golden.mjs drives both. The page's Geolocation is the fake one
// golden.mjs installs (`window.__geo`).
import { Map as MbMap } from "/npm/dist/index.js";
import * as ui from "/npm/dist/ui.js";
import * as maplibregl from "/bench/node_modules/maplibre-gl/dist/maplibre-gl.mjs";

const square = (lng, lat) => ({ type: "Feature", properties: {}, geometry: { type: "Polygon", coordinates: [[[lng, lat], [lng + 0.01, lat], [lng + 0.01, lat + 0.01], [lng, lat + 0.01], [lng, lat]]] } });
const source = (attribution) => ({ type: "geojson", data: { type: "FeatureCollection", features: [square(139.76, 35.68)] }, attribution });
// `?style=` replaces the default style (sources by attribution, for the attribution checks).
const params = new URLSearchParams(location.search);
const given = params.get("style") ? JSON.parse((await (await fetch(params.get("style"))).text()).replaceAll("{origin}", location.origin)) : null;
const style = given ?? {
  version: 8,
  sources: { a: source("Survey A (long)"), b: source("Survey B"), c: source("Survey A"), d: source("Unused"), e: source("Hidden") },
  layers: [
    { id: "bg", type: "background", paint: { "background-color": "#ffffff" } },
    { id: "a", type: "fill", source: "a" },
    { id: "b", type: "fill", source: "b", minzoom: 10 },
    { id: "c", type: "line", source: "c", maxzoom: 14 },
    { id: "e", type: "fill", source: "e", layout: { visibility: "none" } },
  ],
};
const camera = { center: [139.7671, 35.6812], zoom: 12, bearing: 0, pitch: 0, maxZoom: 18 };

const mb = new MbMap({ container: "mbmap", style: structuredClone(style), ...camera, maxPitch: 85, attributionControl: false });
const ml = new maplibregl.Map({ container: "maplibre", style: structuredClone(style), ...camera, maxPitch: 85, attributionControl: false, pixelRatio: 1, fadeDuration: 0 });
const scales = [
  ["metric", 100],
  ["imperial", 150],
  ["nautical", 80],
].map(([unit, maxWidth]) => {
  const control = new maplibregl.ScaleControl({ unit, maxWidth });
  ml.addControl(control);
  return { unit, maxWidth, control };
});
const nav = new maplibregl.NavigationControl({ visualizePitch: true });
ml.addControl(nav);
ml.addControl(new maplibregl.AttributionControl({ compact: false }));
const geolocate = new maplibregl.GeolocateControl({ trackUserLocation: true });
ml.addControl(geolocate);
await Promise.all([mb.once("idle"), new Promise((r) => ml.once("idle", r))]);

const mine = {
  nav: ui.createNavigation(mb),
  attribution: ui.createAttribution(mb),
  geolocation: ui.createGeolocation(mb, { trackUserLocation: true }),
  legend: ui.createLegend(mb),
};
const watchStates = { OFF: "off", WAITING_ACTIVE: "waiting", ACTIVE_LOCK: "active", ACTIVE_ERROR: "active-error", BACKGROUND: "background", BACKGROUND_ERROR: "background-error" };

window.__ui = ui;
window.__mb = mb;
window.__ml = ml;
window.__mine = mine;
window.__theirs = {
  scales: () => scales.map(({ unit, maxWidth, control }) => ({ unit, maxWidth, width: parseFloat(control._container.style.width), label: control._container.textContent })),
  nav: () => ({ canZoomIn: !nav._zoomInButton.disabled, canZoomOut: !nav._zoomOutButton.disabled }),
  attribution: () => ml.getContainer().querySelector(".maplibregl-ctrl-attrib-inner")?.textContent ?? "",
  geolocation: () => (geolocate._geolocateButton.disabled && geolocate._watchState === "OFF" ? "unavailable" : watchStates[geolocate._watchState]),
  geolocate,
  // MapLibre's paint for a feature with `properties` at its zoom: straight RGBA with the opacity in alpha.
  color(id, colorProperty, opacityProperty, properties) {
    const layer = ml.style._layers[id];
    const value = (name) => {
      const v = layer.paint.get(name);
      return typeof v?.evaluate === "function" ? v.evaluate({ type: 3, properties }, {}) : v;
    };
    const c = value(colorProperty);
    const opacity = opacityProperty ? value(opacityProperty) : 1;
    return c.a === 0 ? [0, 0, 0, 0] : [c.r / c.a, c.g / c.a, c.b / c.a, c.a * opacity];
  },
};
window.__ready = true;
