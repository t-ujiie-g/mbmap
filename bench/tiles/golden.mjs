// mbmap/3d's 3D Tiles selection (npm/src/tiles: tree, implicit tiling, traversal) vs @loaders.gl/tiles
// 4.5.4's Tileset3D: for each tileset and view, both traverse with loaders.gl's frame state (from a
// WebMercatorViewport of the camera) and load what they ask for until nothing is left; the tiles
// selected then must be the same. The frame states come from a camera of the golden's own (60° field
// of view, as loaders.gl's sseDenominator assumes), so both traverse the very same one. Tilesets: PLATEAU's Chiyoda buildings (bench/fixtures/plateau-chiyoda,
// when fetched) and synthetic ones written here (boxes with transforms, spheres with ADD refinement,
// empty tiles, a viewer request volume, an external tileset, implicit quadtree and octree regions).
// Usage: node tiles/golden.mjs; writes bench/results/tiles-golden.json.
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";
import { load } from "@loaders.gl/core";
import { Tiles3DLoader } from "@loaders.gl/3d-tiles";
import { Tileset3D } from "@loaders.gl/tiles";
import { Vector3 } from "@math.gl/core";
import { CullingVolume, Plane } from "@math.gl/culling";
import { Ellipsoid } from "@math.gl/geospatial";
import { Document, NodeIO } from "@gltf-transform/core";
import { buildTree, Traversal } from "../../npm/src/tiles/tileset.ts";
import { expandTileset } from "../../npm/src/tiles/implicit.ts";
import { readTileContent, splitB3dm } from "../../npm/src/tiles/content.ts";
import { readdir } from "node:fs/promises";
import { parse } from "@loaders.gl/core";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";

const OUT = path.join(ROOT, "bench/dist/tilesets");
await mkdir(OUT, { recursive: true });

// Mulberry32: the same tilesets on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(20);

/** A tiny glb every synthetic tile points at under its own name. */
async function tinyGlb() {
  const doc = new Document();
  const buf = doc.createBuffer();
  const pos = doc.createAccessor().setType("VEC3").setArray(new Float32Array([0, 0, 0, 1, 0, 0, 0, 1, 0])).setBuffer(buf);
  doc.createScene().addChild(doc.createNode().setMesh(doc.createMesh().addPrimitive(doc.createPrimitive().setAttribute("POSITION", pos))));
  return new NodeIO().writeBinary(doc);
}
const glb = await tinyGlb();

/** Writes `json` as `dir/name` and a glb for each content URI it names (not .json or templates). */
async function write(dir, name, json) {
  await mkdir(path.join(OUT, dir), { recursive: true });
  await writeFile(path.join(OUT, dir, name), JSON.stringify(json));
  const visit = async (t) => {
    const uri = t.content?.uri;
    if (uri && uri.endsWith(".glb") && !uri.includes("{")) {
      await mkdir(path.dirname(path.join(OUT, dir, uri)), { recursive: true });
      await writeFile(path.join(OUT, dir, uri), glb);
    }
    for (const c of t.children ?? []) await visit(c);
  };
  await visit(json.root);
}

const TOKYO = [139.7671, 35.6812];
const enu = [...Ellipsoid.WGS84.eastNorthUpToFixedFrame(Ellipsoid.WGS84.cartographicToCartesian([...TOKYO, 0]))];

/** A quadtree of boxes `size` meters wide in a local east-north-up frame, `depth` levels. */
function boxes(size, depth, prefix = "b") {
  const make = (x, y, s, level, id) => {
    const tile = {
      boundingVolume: { box: [x, y, 50, s / 2, 0, 0, 0, s / 2, 0, 0, 0, 50 + level * 10] },
      geometricError: level < depth ? s / 8 : 0,
      content: { uri: `${prefix}/${id}.glb` },
    };
    if (level === 1 && id.endsWith("3")) tile.viewerRequestVolume = { sphere: [x, y, 0, s * 2] };
    if (level < depth) {
      tile.children = [];
      for (let i = 0; i < 4; i++) {
        if (rand() < 0.12) continue;
        tile.children.push(make(x + ((i & 1) - 0.5) * s / 2, y + ((i >> 1) - 0.5) * s / 2, s / 2, level + 1, `${id}${i}`));
      }
    }
    return tile;
  };
  return make(0, 0, size, 0, "0");
}

/** Spheres in ECEF, ADD refinement, with empty tiles and an external tileset (content under `prefix`: loaders.gl keys tiles by content URL). */
function spheres(depth, external = true, prefix = "s") {
  const center = Ellipsoid.WGS84.cartographicToCartesian([...TOKYO, 0]);
  const make = (offset, r, level, id) => {
    const c = [center[0] + offset[0], center[1] + offset[1], center[2] + offset[2]];
    const tile = { boundingVolume: { sphere: [...c, r] }, geometricError: level < depth ? r / 6 : 0, refine: "ADD" };
    if (!(level === 1 && id.endsWith("1"))) tile.content = { uri: `${prefix}/${id}.glb` };
    if (external && level === 2 && id === "002") tile.content = { uri: "external.json" };
    if (level < depth && !tile.content?.uri.endsWith(".json")) {
      tile.children = [];
      for (let i = 0; i < 3; i++) {
        const a = (i / 3) * Math.PI * 2 + level;
        tile.children.push(make([offset[0] + Math.cos(a) * r / 2, offset[1] + Math.sin(a) * r / 2, offset[2] + (rand() - 0.5) * r / 4], r / 2, level + 1, `${id}${i}`));
      }
    }
    return tile;
  };
  return make([0, 0, 0], 6000, 0, "0");
}

/** A subtree file for `levels` levels of a quadtree or octree with seeded availability. */
function subtree(levels, perTile, childLevels) {
  const tiles = (perTile ** levels - 1) / (perTile - 1);
  const tileBits = new Uint8Array(Math.ceil(tiles / 8));
  const contentBits = new Uint8Array(Math.ceil(tiles / 8));
  // Availability must hold for a tile's parent: mark the root, then children of available tiles.
  const avail = new Array(tiles).fill(false);
  avail[0] = true;
  for (let level = 1, offset = 1; level < levels; offset += perTile ** level, level++) {
    for (let m = 0; m < perTile ** level; m++) avail[offset + m] = avail[offset - perTile ** (level - 1) + (m >> Math.log2(perTile))] && rand() < 0.75;
  }
  avail.forEach((a, i) => {
    if (a) tileBits[i >> 3] |= 1 << (i & 7);
    if (a && rand() < 0.85) contentBits[i >> 3] |= 1 << (i & 7);
  });
  const children = perTile ** levels;
  const childBits = new Uint8Array(Math.ceil(children / 8));
  if (childLevels) for (let i = 0; i < children; i++) if (rand() < 0.3) childBits[i >> 3] |= 1 << (i & 7);
  const pad = (n) => (n + 7) & ~7;
  const bufs = [tileBits, contentBits, childBits];
  let offset = 0;
  const bufferViews = bufs.map((b) => {
    const v = { buffer: 0, byteOffset: offset, byteLength: b.length };
    offset = pad(offset + b.length);
    return v;
  });
  const json = {
    buffers: [{ byteLength: offset }],
    bufferViews,
    tileAvailability: { bitstream: 0, availableCount: avail.filter(Boolean).length },
    contentAvailability: [{ bitstream: 1 }],
    childSubtreeAvailability: childLevels ? { bitstream: 2 } : { constant: 0 },
  };
  let text = new TextEncoder().encode(JSON.stringify(json));
  const jsonLength = pad(text.length);
  const out = new Uint8Array(24 + jsonLength + offset).fill(0);
  const v = new DataView(out.buffer);
  v.setUint32(0, 0x74627573, true);
  v.setUint32(4, 1, true);
  v.setUint32(8, jsonLength, true);
  v.setUint32(16, offset, true);
  out.fill(0x20, 24, 24 + jsonLength);
  out.set(text, 24);
  bufs.forEach((b, i) => out.set(b, 24 + jsonLength + bufferViews[i].byteOffset));
  return out;
}

/** An implicit tileset over a region around Tokyo: subtrees of `subtreeLevels`, `available` levels in all. */
async function implicit(dir, scheme, subtreeLevels, availableLevels) {
  const perTile = scheme === "OCTREE" ? 8 : 4;
  const rad = Math.PI / 180;
  const json = {
    asset: { version: "1.1" },
    geometricError: 4000,
    root: {
      boundingVolume: { region: [139.70 * rad, 35.64 * rad, 139.84 * rad, 35.72 * rad, 0, 400] },
      geometricError: 2000,
      refine: "REPLACE",
      content: { uri: "content/{level}/{x}/{y}/{z}.glb" },
      implicitTiling: { subdivisionScheme: scheme, subtreeLevels, availableLevels, subtrees: { uri: "subtrees/{level}/{x}/{y}/{z}.subtree" } },
    },
  };
  await write(dir, "tileset.json", json);
  // Every subtree and content file the availability could name.
  for (let level = 0; level < availableLevels; level += subtreeLevels) {
    const n = 2 ** level;
    for (let x = 0; x < n; x++) for (let y = 0; y < n; y++) for (let z = 0; z < (perTile === 8 ? n : 1); z++) {
      const p = path.join(OUT, dir, "subtrees", `${level}/${x}/${y}/${z}.subtree`);
      await mkdir(path.dirname(p), { recursive: true });
      await writeFile(p, subtree(subtreeLevels, perTile, level + subtreeLevels < availableLevels));
    }
  }
  for (let level = 0; level < availableLevels; level++) {
    const n = 2 ** level;
    for (let x = 0; x < n; x++) for (let y = 0; y < n; y++) for (let z = 0; z < (perTile === 8 ? n : 1); z++) {
      const p = path.join(OUT, dir, "content", `${level}/${x}/${y}/${z}.glb`);
      await mkdir(path.dirname(p), { recursive: true });
      await writeFile(p, glb);
    }
  }
}

await write("boxes", "tileset.json", { asset: { version: "1.0" }, geometricError: 4000, root: { ...boxes(8000, 5), transform: enu, refine: "REPLACE" } });
await write("spheres", "tileset.json", { asset: { version: "1.0" }, geometricError: 4000, root: spheres(4) });
await write("spheres", "external.json", { asset: { version: "1.0" }, geometricError: 500, root: { ...spheres(2, false, "e"), content: { uri: "s/external-root.glb" } } });
await implicit("quadtree", "QUADTREE", 2, 6);
await implicit("octree", "OCTREE", 2, 4);

/** Cameras around Tokyo Station: position, height above the ellipsoid (m), heading and tilt from straight down (°). */
const VIEWS = [
  { name: "high", lng: 139.7671, lat: 35.6812, height: 9000, heading: 0, tilt: 0 },
  { name: "tilted", lng: 139.766, lat: 35.676, height: 1500, heading: 20, tilt: 55 },
  { name: "low", lng: 139.768, lat: 35.679, height: 400, heading: -40, tilt: 35 },
  { name: "street", lng: 139.7655, lat: 35.6795, height: 120, heading: 150, tilt: 75 },
  { name: "far", lng: 139.77, lat: 35.62, height: 30000, heading: 10, tilt: 40 },
];

/** loaders.gl's frame state (math.gl objects) for camera `v`: a 60° x 77° frustum from 1 m to 10^6 m. */
function frameState(v, frameNumber) {
  const position = Ellipsoid.WGS84.cartographicToCartesian([v.lng, v.lat, v.height]);
  const m = Ellipsoid.WGS84.eastNorthUpToFixedFrame(position);
  const toEcef = (e) => [m[0] * e[0] + m[4] * e[1] + m[8] * e[2], m[1] * e[0] + m[5] * e[1] + m[9] * e[2], m[2] * e[0] + m[6] * e[1] + m[10] * e[2]];
  const [h, t] = [(v.heading * Math.PI) / 180, (v.tilt * Math.PI) / 180];
  const direction = new Vector3(toEcef([Math.sin(h) * Math.sin(t), Math.cos(h) * Math.sin(t), -Math.cos(t)])).normalize();
  const up = new Vector3(toEcef([Math.sin(h) * Math.cos(t), Math.cos(h) * Math.cos(t), Math.sin(t)])).normalize();
  const right = new Vector3(direction).cross(up).normalize();
  const [ty, tx] = [Math.tan(Math.PI / 6), Math.tan(Math.PI / 6) * (800 / 600)];
  const p = new Vector3(position);
  const side = (edge, axis) => {
    const n = new Vector3(edge).cross(axis).normalize();
    if (n.dot(direction) < 0) n.negate();
    return new Plane().fromPointNormal(p, n);
  };
  const planes = [
    new Plane().fromPointNormal(new Vector3(direction).scale(1).add(p), direction),
    new Plane().fromPointNormal(new Vector3(direction).scale(1e6).add(p), new Vector3(direction).negate()),
    side(new Vector3(direction).subtract(new Vector3(right).scale(tx)), up),
    side(new Vector3(direction).add(new Vector3(right).scale(tx)), up),
    side(new Vector3(direction).subtract(new Vector3(up).scale(ty)), right),
    side(new Vector3(direction).add(new Vector3(up).scale(ty)), right),
  ];
  return {
    camera: { position: p, direction, up },
    viewport: { id: "view", longitude: v.lng, latitude: v.lat },
    height: 600,
    cullingVolume: new CullingVolume(planes),
    frameNumber,
    sseDenominator: 1.15,
  };
}

const { server, origin } = await serve();
const fetchBytes = async (url) => new Uint8Array(await (await fetch(url)).arrayBuffer());
const results = [];
let failed = 0;

/** loaders.gl's tile `t` as a path of header indices from the root ("/t" under an external tileset's tile). */
function key(t) {
  if (!t.parent) return "r";
  const i = (t.parent.header.children ?? []).indexOf(t.header);
  return `${key(t.parent)}/${i < 0 ? "t" : i}`;
}

try {
  const sets = { boxes: "bench/dist/tilesets/boxes", spheres: "bench/dist/tilesets/spheres", quadtree: "bench/dist/tilesets/quadtree", octree: "bench/dist/tilesets/octree" };
  if (existsSync(path.join(ROOT, "bench/fixtures/plateau-chiyoda/tileset.json"))) sets["plateau-chiyoda"] = "bench/fixtures/plateau-chiyoda";
  for (const [name, dir] of Object.entries(sets)) {
    const url = `${origin}/${dir}/tileset.json`;
    for (const view of VIEWS) {
      // loaders.gl, loading everything it asks for until it asks for nothing more.
      const theirsJson = await load(url, Tiles3DLoader);
      const tileset = new Tileset3D(theirsJson, { throttleRequests: false, maximumScreenSpaceError: 8, loadOptions: { "3d-tiles": { loadGLTF: false } } });
      await tileset.tilesetInitializationPromise;
      const frames = [];
      let theirs;
      for (let n = 1; n < 40; n++) {
        const frame = frameState(view, n);
        frames.push(frame);
        tileset._traverser.traverse(tileset.root, frame, tileset.options);
        const requested = Object.values(tileset._traverser.requestedTiles);
        theirs = Object.values(tileset._traverser.selectedTiles).map(key).sort();
        if (!requested.length) break;
        // Tiles outside the fixture's box are missing: both sides count them as failed.
        await Promise.all(requested.map((t) => t.loadContent().catch(() => {})));
      }
      // mbmap, with the same frame state.
      const json = await expandTileset(JSON.parse(new TextDecoder().decode(await fetchBytes(url))), url, fetchBytes);
      const root = buildTree(json, url);
      const traversal = new Traversal(8);
      let ours;
      for (let n = 0; n < 40; n++) {
        const f = frames[Math.min(n, frames.length - 1)];
        traversal.traverse(root, {
          position: [...f.camera.position], direction: [...f.camera.direction], up: [...f.camera.up],
          planes: f.cullingVolume.planes.map((p) => ({ normal: [...p.normal], distance: p.distance })),
          height: f.height, sseDenominator: f.sseDenominator,
        });
        ours = [...traversal.selected.keys()].sort();
        if (!traversal.requested.size) break;
        for (const t of traversal.requested.values()) {
          if (t.contentUrl.endsWith(".json")) {
            const sub = await expandTileset(JSON.parse(new TextDecoder().decode(await fetchBytes(t.contentUrl))), t.contentUrl, fetchBytes);
            buildTree(sub, t.contentUrl, t);
            t.isTileset = true;
          }
          else t.state = (await fetch(t.contentUrl, { method: "HEAD" })).ok ? "ready" : "failed";
          if (t.isTileset) t.state = "ready";
        }
      }
      const same = JSON.stringify(ours) === JSON.stringify(theirs);
      if (!same) failed++;
      const onlyOurs = ours.filter((k) => !theirs.includes(k));
      const onlyTheirs = theirs.filter((k) => !ours.includes(k));
      results.push({ tileset: name, view: view.name, same, selected: theirs.length, onlyOurs: onlyOurs.slice(0, 5), onlyTheirs: onlyTheirs.slice(0, 5) });
    }
  }
  // Contents: the b3dm tables (and RTC_CENTER) as loaders.gl reads them; the synthetic ones' glTF too.
  const b3dms = [];
  for (const dir of ["bench/npm/pages/tiles/set", "bench/fixtures/plateau-chiyoda/data"]) {
    if (!existsSync(path.join(ROOT, dir))) continue;
    for (const f of (await readdir(path.join(ROOT, dir))).filter((f) => f.endsWith(".b3dm"))) b3dms.push(path.join(dir, f));
  }
  let contentsDiffer = 0;
  for (const file of b3dms) {
    const bytes = new Uint8Array(await readFile(path.join(ROOT, file)));
    const theirs = await parse(bytes, Tiles3DLoader, { "3d-tiles": { loadGLTF: false } });
    const ours = splitB3dm(bytes);
    const same =
      ours.batchLength === (theirs.featureTableJson.BATCH_LENGTH ?? 0) &&
      JSON.stringify(ours.batchTable ?? {}) === JSON.stringify(theirs.batchTableJson ?? {}) &&
      JSON.stringify(ours.rtc) === JSON.stringify(theirs.rtcCenter ? [...theirs.rtcCenter] : null);
    let model = true;
    if (file.includes("/set/")) {
      const full = await readTileContent(bytes, async () => new Uint8Array());
      model = full.model.primitives.length > 0 && full.batchLength === ours.batchLength;
    }
    if (!same || !model) contentsDiffer++;
  }
  results.push({ contents: b3dms.length, differ: contentsDiffer });
  if (contentsDiffer) failed++;
} finally {
  server.close();
}
await writeFile(path.join(ROOT, "bench/results/tiles-golden.json"), JSON.stringify({ env: { loaders: "@loaders.gl/tiles 4.5.4" }, results }, null, 2) + "\n");
for (const r of results) console.log(JSON.stringify(r));
console.log(`tiles golden: ${results.length - failed} of ${results.length} the same`);
if (failed) process.exit(1);
