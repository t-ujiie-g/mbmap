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

// Each shown label as `layer z/x/y feature@x,y` (anchor in MapLibre's 8192 tile units) with its
// anchor, box (CSS px) and, along lines, its glyphs' screen positions and angles.
function mbmapLabels() {
  return mbmap.map_placed_labels(mb).split("\n").filter(Boolean).map((line) => {
    const [layer, z, x, y, feature, ax, ay, code, b0, b1, b2, b3, glyphs] = line.split(",");
    return {
      key: `${layer} ${z}/${x}/${y} ${feature}@${ax},${ay}`,
      anchor: Number(code) < 0 ? null : ANCHORS[Number(code)],
      box: [b0, b1, b2, b3].map(Number),
      glyphs: glyphs ? glyphs.trim().split(" ").map((g) => g.split(":").map(Number)) : null,
    };
  });
}

function maplibreLabels() {
  const placement = ml.style.placement;
  const transform = placement.transform;
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
      const along = layer.layout?.["symbol-placement"] === "line" || layer.layout?.["symbol-placement"] === "line-center";
      // Label plane pixels to tile units, for text pitched with the map.
      const toTile = 8192 / (tile.tileSize * 2 ** (transform.zoom - tile.tileID.overscaledZ));
      const dynamic = bucket.text.dynamicLayoutVertexArray.float32;
      for (let i = 0; i < bucket.symbolInstances.length; i++) {
        const s = bucket.symbolInstances.get(i);
        // A label with variable anchors but none placed has its glyphs hidden (`hideGlyphs`).
        const variable = s.textAnchorOffsetEndIndex > s.textAnchorOffsetStartIndex;
        if (!placement.placements[s.crossTileID]?.text || (variable && !placement.variableOffsets[s.crossTileID])) continue;
        let glyphs = null;
        if (along) {
          const ps = bucket.text.placedSymbolArray.get(s.centerJustifiedTextSymbolIndex);
          glyphs = [];
          for (let g = ps.glyphStartIndex; g < ps.glyphStartIndex + ps.numGlyphs; g++) {
            const [lx, ly, angle] = dynamic.slice(g * 12, g * 12 + 3);
            const p = transform.projectTileCoordinates(lx * toTile, ly * toTile, tile.tileID.toUnwrapped());
            glyphs.push([(p.point.x + 1) / 2 * transform.width, (1 - p.point.y) / 2 * transform.height, angle]);
          }
        }
        out.push({
          key: `${layer.id} ${z}/${x}/${y} ${s.featureIndex}@${s.anchorX},${s.anchorY}`,
          anchor: placement.variableOffsets[s.crossTileID]?.anchor ?? null,
          box: boxes.get(`${bucket.bucketInstanceId} ${s.featureIndex}`) ?? null,
          glyphs,
        });
      }
    }
  }
  return out;
}

window.__placed = () => ({ mbmap: mbmapLabels(), maplibre: maplibreLabels() });
window.__ml = ml;
window.__ready = true;
