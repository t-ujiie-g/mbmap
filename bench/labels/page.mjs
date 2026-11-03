// mbmap's engine and MapLibre side by side with one style and camera; bench/labels/golden.mjs
// reads the labels each placed through `window.__placed`. Needs `npm --prefix npm run build`.
import * as mbmap from "/_build/js/release/build/bundle/main/main.js";
import * as maplibregl from "/bench/node_modules/maplibre-gl/dist/maplibre-gl.mjs";

const params = new URLSearchParams(location.search);
const styleText = (await (await fetch(params.get("style"))).text()).replaceAll("{origin}", location.origin);
const styleJson = JSON.parse(styleText);
const camera = JSON.parse(params.get("camera"));
const { center: [lng, lat], zoom, bearing = 0, pitch = 0 } = camera;

const canvas = document.getElementById("mbmap");
const mb = mbmap.create_map(canvas, styleText, lng, lat, zoom, bearing, pitch, "/worker/js/worker.mjs",
  "/_build/wasm-gc/release/build/worker/worker.wasm", 0, null, "sans-serif", [0, 22, 0, 85, NaN, 0, 0, 0]);
const ml = new maplibregl.Map({ container: "maplibre", style: JSON.parse(styleText), ...camera, maxPitch: 85, attributionControl: false, pixelRatio: 1, fadeDuration: 0, zoomLevelsToOverscale: undefined });
// The same images in both, drawn from functions of the pixel: a dot, a framed box, a pin at
// 2x, an SDF ring (alpha 192 on its edge); scenes also ask for "nope", which neither has.
function image(w, h, at) {
  const data = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) data.set(at((x + 0.5) / w, (y + 0.5) / h), (y * w + x) * 4);
  return { width: w, height: h, data };
}
const IMAGES = {
  dot: [image(12, 12, (u, v) => (Math.hypot(u - 0.5, v - 0.5) < 0.42 ? [210, 50, 40, 255] : [0, 0, 0, 0])), 1, false],
  box: [image(16, 10, (u, v) => (u < 0.1 || u > 0.9 || v < 0.15 || v > 0.85 ? [20, 40, 120, 255] : [120, 170, 240, 230])), 1, false],
  pin: [image(20, 28, (u, v) => (Math.hypot(u - 0.5, v - 0.35) < 0.4 || (v > 0.35 && Math.abs(u - 0.5) < 0.4 * (1 - v)) ? [30, 130, 60, 255] : [0, 0, 0, 0])), 2, false],
  ring: [image(24, 24, (u, v) => [0, 0, 0, Math.max(0, Math.min(255, Math.round(192 - Math.abs(Math.hypot(u - 0.5, v - 0.5) * 24 - 7) * 16)))]), 1, true],
};
for (const [name, [img, pixelRatio, sdf]] of Object.entries(IMAGES)) {
  mbmap.map_add_image(mb, name, img.width, img.height, img.data, pixelRatio, sdf);
  ml.addImage(name, img, { pixelRatio, sdf });
}

const mbIdle = () => new Promise((r) => { const id = mbmap.map_on_idle(mb, () => { mbmap.map_off(mb, id); r(); }); });
await Promise.all([mbIdle(), new Promise((r) => ml.once("idle", r))]);
await new Promise((r) => setTimeout(r, 500));

// The anchor names in worker/labels.mbt's codes.
const ANCHORS = ["center", "left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right"];
// A multi-line label's layouts in worker/js/symbols.mjs, in order.
const JUSTIFY = ["left", "center", "right"];

// Each shown label as `layer z/x/y feature@x,y` (anchor in MapLibre's 8192 tile units) with its
// anchor, whether its text and its icon show, its text's justification if it has several layouts, the boxes it put in the collision grid (CSS px:
// its text's, then its icon's) and, along lines, its glyphs' screen positions and angles.
function mbmapLabels() {
  const ignored = (layer, key) => styleJson.layers.find((l) => l.id === layer)?.layout?.[key] === true;
  return mbmap.map_placed_labels(mb).split("\n").filter(Boolean).map((line) => {
    const [layer, z, x, y, feature, ax, ay, code, t, i, layout, ...rest] = line.split(",");
    const box = rest.slice(0, 8).map(Number);
    const boxes = [];
    // Text along lines goes in the grid as circles, which MapLibre keeps apart from boxes.
    const along = (styleJson.layers.find((l) => l.id === layer)?.layout?.["symbol-placement"] ?? "point") !== "point";
    if (t === "1" && !along && !ignored(layer, "text-ignore-placement") && Number.isFinite(box[0])) boxes.push(box.slice(0, 4));
    if (i === "1" && !ignored(layer, "icon-ignore-placement") && Number.isFinite(box[4])) boxes.push(box.slice(4));
    return {
      key: `${layer} ${z}/${x}/${y} ${feature}@${ax},${ay}`,
      anchor: Number(code) < 0 ? null : ANCHORS[Number(code)],
      text: t === "1",
      icon: i === "1",
      justify: JUSTIFY[Number(layout)] ?? null,
      box: boxes,
      glyphs: rest[8] ? rest[8].trim().split(" ").map((g) => g.split(":").map(Number)) : null,
    };
  });
}

function maplibreLabels() {
  const placement = ml.style.placement;
  const transform = placement.transform;
  // The boxes each feature put in the grid, in order (its text's before its icon's).
  const boxes = new Map();
  const grid = placement.collisionIndex.grid;
  for (let i = 0; i < grid.boxKeys.length; i++) {
    const k = grid.boxKeys[i];
    const key = `${k.bucketInstanceId} ${k.featureIndex}`;
    boxes.set(key, [...(boxes.get(key) ?? []), [...grid.bboxes.slice(i * 4, i * 4 + 4)].map((v) => v - 100)]);
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
        const placed = placement.placements[s.crossTileID];
        const text = !!placed?.text && s.numHorizontalGlyphVertices + s.numVerticalGlyphVertices > 0 && !(variable && !placement.variableOffsets[s.crossTileID]);
        const icon = !!placed?.icon && s.numIconVertices > 0;
        if (!text && !icon) continue;
        // The layout shown when the label has several (`markUsedJustification`).
        const indices = [s.leftJustifiedTextSymbolIndex, s.centerJustifiedTextSymbolIndex, s.rightJustifiedTextSymbolIndex];
        const several = new Set(indices.filter((k) => k >= 0)).size > 1;
        const justify = text && several
          ? JUSTIFY.find((_, k) => indices[k] >= 0 && bucket.text.placedSymbolArray.get(indices[k]).crossTileID === s.crossTileID) ?? null
          : null;
        let glyphs = null;
        if (along) {
          const ps = bucket.text.placedSymbolArray.get(s.centerJustifiedTextSymbolIndex);
          glyphs = [];
          // Glyph offsets are shared with icons, so a glyph's place is found by its vertices (4 each).
          for (let g = 0; g < (s.numHorizontalGlyphVertices > 0 ? ps.numGlyphs : 0); g++) {
            const [lx, ly, angle] = dynamic.slice((ps.vertexStartIndex + g * 4) * 3, (ps.vertexStartIndex + g * 4) * 3 + 3);
            const p = transform.projectTileCoordinates(lx * toTile, ly * toTile, tile.tileID.toUnwrapped());
            glyphs.push([(p.point.x + 1) / 2 * transform.width, (1 - p.point.y) / 2 * transform.height, angle]);
          }
        }
        out.push({
          key: `${layer.id} ${z}/${x}/${y} ${s.featureIndex}@${s.anchorX},${s.anchorY}`,
          anchor: text ? placement.variableOffsets[s.crossTileID]?.anchor ?? null : null,
          text,
          icon,
          justify,
          box: boxes.get(`${bucket.bucketInstanceId} ${s.featureIndex}`) ?? [],
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
