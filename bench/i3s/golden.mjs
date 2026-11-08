// mbmap/3d's I3S node selection (npm/src/i3s/scene.ts on the shared traversal) vs @loaders.gl/tiles
// 4.5.4's Tileset3D with @loaders.gl/i3s 4.5.4: for each view both traverse the same frame state and
// load every node page and content they ask for (contents marked loaded, not read) until nothing is
// left; the nodes selected must be the same. The layer is Esri's San Francisco buildings sample, its
// layer document and node pages served from bench/fixtures/i3s-sf-pages. Usage: node i3s/golden.mjs
import http from "node:http";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { load } from "@loaders.gl/core";
import { I3SLoader } from "@loaders.gl/i3s";
import { Tileset3D, TILE_CONTENT_STATE } from "@loaders.gl/tiles";
import { CullingVolume, Plane } from "@math.gl/culling";
import { Vector3 } from "@math.gl/core";
import { Ellipsoid } from "@math.gl/geospatial";
import { frameState } from "../../npm/src/tiles/frame.ts";
import { Traversal } from "../../npm/src/tiles/tileset.ts";
import { lodStatus, nodeById, nodeTile, projector, readLayer } from "../../npm/src/i3s/scene.ts";
import { ROOT } from "../lib/root.mjs";

const DIR = path.join(ROOT, "bench/fixtures/i3s-sf-pages");
if (!existsSync(path.join(DIR, "layer.json"))) {
  console.error("i3s golden: no fixture; run `npm run fixtures -- --only=i3s-sf-pages` first");
  process.exit(1);
}

// The layer as a SceneServer would give it: /layers/0 and /layers/0/nodepages/<n>.
const server = http.createServer(async (req, res) => {
  const { pathname } = new URL(req.url, "http://x");
  const m = /^\/layers\/0(?:\/nodepages\/(\d+))?$/.exec(pathname);
  const file = m && (m[1] === undefined ? "layer.json" : `nodepages/${m[1]}`);
  const body = file && (await readFile(path.join(DIR, file)).catch(() => null));
  res.writeHead(body ? 200 : 404, { "content-type": "application/json" }).end(body ?? "");
});
await new Promise((done) => server.listen(0, "127.0.0.1", done));
const url = `http://127.0.0.1:${server.address().port}/layers/0`;

const W = 800;
const H = 600;
const FOV = 2 * Math.atan(0.75);

/** MapLibre's Web Mercator view-projection (0 to 1 coordinates, heights in the same units) for a camera at `v`. */
function viewMatrix(v) {
  const ws = 512 * 2 ** v.zoom;
  const dist = (0.5 / Math.tan(FOV / 2)) * H;
  const cx = (v.lng + 180) / 360;
  const cy = (1 - Math.log(Math.tan(Math.PI / 4 + (v.lat * Math.PI) / 360)) / Math.PI) / 2;
  const mul = (a, b) => Array.from({ length: 16 }, (_, i) => [0, 1, 2, 3].reduce((s, k) => s + a[k * 4 + (i % 4)] * b[Math.floor(i / 4) * 4 + k], 0));
  const f = 1 / Math.tan(FOV / 2);
  const [near, far] = [dist / 50, dist * 200];
  const persp = [f / (W / H), 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) / (near - far), -1, 0, 0, (2 * far * near) / (near - far), 0];
  const p = (v.pitch * Math.PI) / 180;
  const b = (v.bearing * Math.PI) / 180;
  const rotX = [1, 0, 0, 0, 0, Math.cos(p), Math.sin(p), 0, 0, -Math.sin(p), Math.cos(p), 0, 0, 0, 0, 1];
  const rotZ = [Math.cos(b), -Math.sin(b), 0, 0, Math.sin(b), Math.cos(b), 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  const t = (x, y, z) => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1];
  const s = (x, y, z) => [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1];
  let m = mul(persp, t(0, 0, -dist));
  m = mul(m, rotX);
  m = mul(m, rotZ);
  m = mul(m, s(ws, -ws, ws));
  return mul(m, t(-cx, -cy, 0));
}

/** loaders.gl's frame state from ours: the same camera, planes and screen projection. */
function theirFrame(ours, frameNumber) {
  const project = projector(ours);
  return {
    camera: { position: new Vector3(ours.position), direction: new Vector3(ours.direction), up: new Vector3(ours.up) },
    viewport: { id: "view" },
    topDownViewport: { cameraPosition: ours.position, project, unprojectPosition: (p) => Ellipsoid.WGS84.cartesianToCartographic(p, [0, 0, 0]) },
    height: H,
    cullingVolume: new CullingVolume(ours.planes.map((p) => new Plane(p.normal, p.distance))),
    frameNumber,
    sseDenominator: ours.sseDenominator,
  };
}

/** Cameras over San Francisco: center, zoom, pitch and bearing (°). */
const VIEWS = [
  { name: "city", lng: -122.43, lat: 37.765, zoom: 12.5, pitch: 0, bearing: 0 },
  { name: "downtown", lng: -122.4, lat: 37.79, zoom: 15, pitch: 45, bearing: -30 },
  { name: "street", lng: -122.396, lat: 37.7935, zoom: 17.5, pitch: 70, bearing: 120 },
  { name: "mission", lng: -122.418, lat: 37.76, zoom: 16, pitch: 60, bearing: 200 },
  { name: "edge", lng: -122.5, lat: 37.72, zoom: 14, pitch: 30, bearing: 80 },
];

const fetchJson = async (u) => JSON.parse(await (await fetch(u)).text());
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const results = [];
let failed = 0;
try {
  for (const view of VIEWS) {
    const ours = frameState(viewMatrix(view), H, false, W);
    // loaders.gl: node pages load as it asks; contents are marked loaded, not read.
    const tileset = new Tileset3D(await load(url, I3SLoader, { i3s: { useDracoGeometry: true } }), { throttleRequests: false });
    await tileset.tilesetInitializationPromise;
    const traverser = tileset._traverser;
    // Its traversals end by loading contents (Tileset3D._onTraversalEnd); here contents are marked loaded instead.
    const quiet = { ...tileset.options, onTraversalEnd: () => {} };
    let theirs = [];
    for (let n = 1; n < 200; n++) {
      const frame = theirFrame(ours, n);
      traverser.traverse(tileset.root, frame, quiet);
      while (traverser._tileManager.hasPendingTiles("view", n)) await sleep(5);
      traverser.traverse(tileset.root, frame, quiet);
      const requested = Object.values(traverser.requestedTiles);
      theirs = Object.values(traverser.selectedTiles).map((t) => t.id.replace(/-view$/, "")).sort();
      if (!requested.length && !traverser._tileManager.hasPendingTiles("view", n)) break;
      for (const t of requested) t.contentState = TILE_CONTENT_STATE.READY;
    }
    // mbmap, with the same frame state.
    const layer = readLayer(await fetchJson(url), url);
    const root = nodeTile(layer, await nodeById(layer, 0, fetchJson), null);
    const traversal = new Traversal(8, (tile, frame) => lodStatus(tile, frame) === "DIG");
    let mine = [];
    for (let n = 0; n < 200; n++) {
      traversal.traverse(root, ours);
      mine = [...traversal.selected.keys()].sort();
      if (!traversal.requested.size && !traversal.expand.size) break;
      for (const tile of traversal.expand.values()) {
        for (const id of tile.header.children) nodeTile(layer, await nodeById(layer, id, fetchJson), tile);
      }
      for (const tile of traversal.requested.values()) tile.state = "ready";
    }
    const same = JSON.stringify(mine) === JSON.stringify(theirs);
    if (!same) failed++;
    const onlyOurs = mine.filter((k) => !theirs.includes(k));
    const onlyTheirs = theirs.filter((k) => !mine.includes(k));
    results.push({ view: view.name, selected: mine.length, same, onlyOurs: onlyOurs.slice(0, 10), onlyTheirs: onlyTheirs.slice(0, 10) });
  }
} finally {
  server.close();
}
await mkdir(path.join(ROOT, "bench/results"), { recursive: true });
await writeFile(path.join(ROOT, "bench/results/i3s-golden.json"), JSON.stringify({ env: { loaders: "@loaders.gl/tiles 4.5.4, @loaders.gl/i3s 4.5.4", layer: "SanFrancisco_Bldgs" }, results }, null, 2) + "\n");
for (const r of results) console.log(JSON.stringify(r));
console.log(`i3s golden: ${results.length - failed} of ${results.length} the same`);
if (failed) process.exit(1);
