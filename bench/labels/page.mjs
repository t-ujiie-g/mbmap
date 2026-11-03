// mbmap's engine and MapLibre side by side with one style and camera; bench/labels/golden.mjs
// reads the labels each placed through `window.__placed`. Needs `npm --prefix npm run build`.
import * as mbmap from "/_build/js/release/build/bundle/main/main.js";
import * as maplibregl from "/bench/node_modules/maplibre-gl/dist/maplibre-gl.mjs";

const params = new URLSearchParams(location.search);
const styleText = (await (await fetch(params.get("style"))).text()).replaceAll("{origin}", location.origin);
const camera = JSON.parse(params.get("camera"));
const { center: [lng, lat], zoom, bearing = 0, pitch = 0 } = camera;

const canvas = document.getElementById("mbmap");
const mb = mbmap.create_map(canvas, styleText, lng, lat, zoom, bearing, pitch, "/worker/js/worker.mjs",
  "/_build/wasm-gc/release/build/worker/worker.wasm", 0, null, "sans-serif", [0, 22, 0, 85, NaN, 0, 0, 0]);
const ml = new maplibregl.Map({ container: "maplibre", style: JSON.parse(styleText), ...camera, maxPitch: 85, attributionControl: false, pixelRatio: 1, fadeDuration: 0, zoomLevelsToOverscale: undefined });
const mbIdle = () => new Promise((r) => { const id = mbmap.map_on_idle(mb, () => { mbmap.map_off(mb, id); r(); }); });
await Promise.all([mbIdle(), new Promise((r) => ml.once("idle", r))]);
await new Promise((r) => setTimeout(r, 500));

// The anchor names in worker/labels.mbt's codes.
const ANCHORS = ["center", "left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right"];
// MapLibre's tile units are twice those of mbmap (8192 against `@core.TILE_EXTENT` 4096).
const SCALE = 2;

// Each shown label as `layer z/x/y feature@x,y` with its anchor and box (CSS px).
function mbmapLabels() {
  return mbmap.map_placed_labels(mb).split("\n").filter(Boolean).map((line) => {
    const [layer, z, x, y, feature, ax, ay, code, ...box] = line.split(",");
    return { key: `${layer} ${z}/${x}/${y} ${feature}@${ax},${ay}`, anchor: Number(code) < 0 ? null : ANCHORS[Number(code)], box: box.map(Number) };
  });
}

function maplibreLabels() {
  const placement = ml.style.placement;
  const boxes = new Map();
  const grid = placement.collisionIndex.grid;
  for (let i = 0; i < grid.boxKeys.length; i++) {
    const k = grid.boxKeys[i];
    boxes.set(`${k.bucketInstanceId} ${k.featureIndex}`, [...grid.bboxes.slice(i * 4, i * 4 + 4)].map((v) => v - 100));
  }
  const out = [];
  for (const layer of ml.getStyle().layers.filter((l) => l.type === "symbol")) {
    const tm = ml.style.tileManagers[layer.source];
    for (const id of tm.getRenderableIds(true)) {
      const tile = tm.getTileByID(id);
      const bucket = tile.getBucket(ml.style._layers[layer.id]);
      if (!bucket) continue;
      const { z, x, y } = tile.tileID.canonical;
      for (let i = 0; i < bucket.symbolInstances.length; i++) {
        const s = bucket.symbolInstances.get(i);
        // A label with variable anchors but none placed has its glyphs hidden (`hideGlyphs`).
        const variable = s.textAnchorOffsetEndIndex > s.textAnchorOffsetStartIndex;
        if (!placement.placements[s.crossTileID]?.text || (variable && !placement.variableOffsets[s.crossTileID])) continue;
        out.push({
          key: `${layer.id} ${z}/${x}/${y} ${s.featureIndex}@${s.anchorX / SCALE},${s.anchorY / SCALE}`,
          anchor: placement.variableOffsets[s.crossTileID]?.anchor ?? null,
          box: boxes.get(`${bucket.bucketInstanceId} ${s.featureIndex}`) ?? null,
        });
      }
    }
  }
  return out;
}

window.__placed = () => ({ mbmap: mbmapLabels(), maplibre: maplibreLabels() });
window.__ml = ml;
window.__ready = true;
