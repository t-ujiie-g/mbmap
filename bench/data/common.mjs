// What the data goldens share: the wasm builds, the comparison of rows, GSI's features
// (国土地理院ベクトルタイル提供実験).
import { readFile } from "node:fs/promises";
import path from "node:path";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { ROOT } from "../lib/root.mjs";

export const wasmFile = (name) => readFile(path.join(ROOT, `_build/wasm-gc/release/build/${name}/${name}.wasm`));

// Equal as JSON with numbers by Object.is, or within `eps` if given; a Date of papaparse equals
// the ISO string it came from.
export function same(a, b, eps = 0) {
  if (b instanceof Date) return typeof a === "string" && new Date(a).getTime() === b.getTime();
  if (typeof a === "number" && typeof b === "number" && eps > 0) return Math.abs(a - b) <= eps;
  if (typeof a === "number" || typeof b === "number") return Object.is(a, b);
  if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return a === b;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  const ka = Object.keys(a);
  const kb = Object.keys(b);
  return ka.length === kb.length && ka.every((k) => Object.hasOwn(b, k) && same(a[k], b[k], eps));
}

export const GSI_TILES = ["14/14552/6451", "14/14551/6450", "14/14553/6452"];
const LAYERS = ["label", "road", "building", "contour", "railway", "waterarea"];

/** GeoJSON features of `GSI_TILES` by layer of `LAYERS` and `more`; `id` gives each an id from its tile's key and index. */
export async function gsiFeatures({ more = [], id = false } = {}) {
  const { tiles } = JSON.parse(await readFile(path.join(ROOT, "bench/fixtures/gsi-bvmap.manifest.json"), "utf8"));
  if (!GSI_TILES.every((k) => k in tiles)) throw new Error("no GSI fixtures: run npm run fixtures");
  const byLayer = {};
  for (const key of GSI_TILES) {
    const [z, x, y] = key.split("/").map(Number);
    const tile = new VectorTile(new PbfReader(await readFile(path.join(ROOT, "bench/fixtures/gsi-bvmap", `${key}.pbf`))));
    for (const name of [...LAYERS, ...more]) {
      const layer = tile.layers[name];
      for (let i = 0; layer && i < layer.length; i++) {
        const f = layer.feature(i).toGeoJSON(x, y, z);
        (byLayer[name] ??= []).push(id ? { ...f, id: `${key}/${i}` } : f);
      }
    }
  }
  return byLayer;
}
