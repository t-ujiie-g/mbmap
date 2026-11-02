// mbmap (the npm build) and MapLibre side by side with one style and camera;
// bench/query/golden.mjs queries both through `window.__query`.
import { Map as MbMap } from "/npm/dist/index.js";
import * as maplibregl from "/bench/node_modules/maplibre-gl/dist/maplibre-gl.mjs";

const params = new URLSearchParams(location.search);
const style = JSON.parse((await (await fetch(params.get("style"))).text()).replaceAll("{origin}", location.origin));
const camera = JSON.parse(params.get("camera"));

const mb = new MbMap({ container: "mbmap", style: structuredClone(style), ...camera, maxPitch: 85 });
// MapLibre 6 splits tiles deeper than a source's maxzoom by default, which changes what
// queries return (`zoomLevelsToOverscale`); mbmap draws, and queries, the source's own tiles.
const ml = new maplibregl.Map({ container: "maplibre", style: structuredClone(style), ...camera, maxPitch: 85, attributionControl: false, pixelRatio: 1, fadeDuration: 0, zoomLevelsToOverscale: undefined });
await Promise.all([mb.once("idle"), new Promise((r) => ml.once("idle", r))]);
// Both have every tile and have placed their labels.
await new Promise((r) => setTimeout(r, 500));

// A feature as both engines can be compared: what drew it and what it is.
const plain = (f) => ({
  layer: f.layer?.id,
  source: f.source,
  sourceLayer: f.sourceLayer,
  id: f.id,
  state: f.state,
  geometry: f.geometry,
  properties: Object.fromEntries(Object.entries(f.properties).sort(([a], [b]) => (a < b ? -1 : 1))),
});

// The same feature states on both maps, once both have drawn them.
window.__setState = async (states) => {
  const idle = Promise.all([mb.once("idle"), new Promise((r) => ml.once("idle", r))]);
  for (const [feature, state] of states) {
    mb.setFeatureState(feature, state);
    ml.setFeatureState(feature, state);
  }
  ml.triggerRepaint();
  await idle;
};

window.__query = async (kind, geometry, options) => {
  if (kind === "source") {
    const [source, o] = geometry;
    return { mbmap: (await mb.querySourceFeatures(source, o)).map(plain), maplibre: ml.querySourceFeatures(source, o).map(plain) };
  }
  return {
    mbmap: (await mb.queryRenderedFeatures(geometry ?? undefined, options)).map(plain),
    maplibre: (geometry ? ml.queryRenderedFeatures(geometry, options) : ml.queryRenderedFeatures(options)).map(plain),
  };
};
window.__ml = ml; window.__mb = mb;
window.__ready = true;
