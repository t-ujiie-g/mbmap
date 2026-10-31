// GeoJSON test data, generated (deterministically) into bench/dist/geojson/:
// layers of the GSI bench tiles as lng/lat GeoJSON, and seeded random
// features around the world that cross the antimeridian and reach high
// latitudes. Attribution of the GSI data: 国土地理院ベクトルタイル提供実験.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { VectorTile } from "@mapbox/vector-tile";
import { PbfReader } from "pbf";
import { ROOT } from "../lib/root.mjs";

const OUT = path.join(ROOT, "bench/dist/geojson");

// The 3 x 3 tiles around Tokyo Station (14/14552/6451), for the dense layers.
const CENTER = new Set(["14551", "14552", "14553"].flatMap((x) => ["6450", "6451", "6452"].map((y) => `14/${x}/${y}`)));

function fromTiles(manifest, layers, only) {
  const features = [];
  for (const key of Object.keys(manifest.tiles)) {
    if (only && !only.has(key)) continue;
    const [z, x, y] = key.split("/").map(Number);
    const tile = new VectorTile(new PbfReader(readTile(key)));
    for (const name of layers) {
      const layer = tile.layers[name];
      if (!layer) continue;
      for (let i = 0; i < layer.length; i++) features.push(layer.feature(i).toGeoJSON(x, y, z));
    }
  }
  return { type: "FeatureCollection", features };
}

let readTile;

function world(seed, count) {
  let s = seed;
  const rand = () => ((s = (Math.imul(s, 1103515245) + 12345) >>> 0) / 4294967296);
  const features = [];
  for (let i = 0; i < count; i++) {
    const cx = -200 + rand() * 400; // some past ±180
    const cy = -88 + rand() * 176;
    const r = 0.5 + rand() * 20;
    const kind = i % 3;
    const n = 3 + Math.floor(rand() * 12);
    const ring = [];
    for (let k = 0; k < n; k++) {
      const a = (k / n) * 2 * Math.PI;
      ring.push([cx + r * Math.cos(a) * (0.5 + rand()), Math.max(-89, Math.min(89, cy + r * Math.sin(a) * (0.5 + rand())))]);
    }
    const props = { i, name: `f${i}`, even: i % 2 === 0 };
    if (kind === 0) {
      ring.push(ring[0]);
      features.push({ type: "Feature", properties: props, geometry: { type: "Polygon", coordinates: [ring] } });
    } else if (kind === 1) {
      features.push({ type: "Feature", properties: props, geometry: { type: "LineString", coordinates: ring } });
    } else {
      features.push({ type: "Feature", properties: props, geometry: { type: "MultiPoint", coordinates: ring } });
    }
  }
  return { type: "FeatureCollection", features };
}

// Writes the datasets and returns their paths by name.
export async function makeGeoJSONFixtures() {
  await mkdir(OUT, { recursive: true });
  const manifest = JSON.parse(await readFile(path.join(ROOT, "bench/fixtures/gsi-bvmap.manifest.json"), "utf8"));
  const bufs = new Map();
  for (const key of Object.keys(manifest.tiles)) {
    bufs.set(key, new Uint8Array(await readFile(path.join(ROOT, `bench/fixtures/gsi-bvmap/${key}.pbf`))));
  }
  readTile = (key) => bufs.get(key);
  const sets = {
    buildings: fromTiles(manifest, ["building"], CENTER),
    roads: fromTiles(manifest, ["road", "railway", "river"]),
    points: fromTiles(manifest, ["symbol", "label", "elevation"]),
    mixed: fromTiles(manifest, ["building", "road", "waterarea", "symbol", "contour"], CENTER),
    world: world(42, 3000),
  };
  // Roads with coordinates rounded to 6 decimals (about 10 cm), as most
  // GeoJSON in the wild is; the full-precision sets above stress the
  // reader's slow number path.
  sets.roads6 = JSON.parse(JSON.stringify(sets.roads, (k, v) => (typeof v === "number" && k !== "i" ? Math.round(v * 1e6) / 1e6 : v)));
  const files = {};
  for (const [name, data] of Object.entries(sets)) {
    files[name] = path.join(OUT, `${name}.geojson`);
    await writeFile(files[name], JSON.stringify(data));
  }
  return files;
}
