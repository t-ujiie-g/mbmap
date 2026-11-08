import assert from "node:assert/strict";
import test from "node:test";
import { boundingVolume, distanceSquaredTo, eastNorthUp, intersectPlane, INSIDE, INTERSECTING, MASK_INSIDE, MASK_OUTSIDE, OUTSIDE, planeFromPointNormal, toCartesian, toCartographic, visibilityWithPlaneMask } from "../src/tiles/geo.ts";
import { buildTree, Traversal, type FrameState } from "../src/tiles/tileset.ts";
import { expandImplicit, readSubtree } from "../src/tiles/implicit.ts";
import { frameState, invert } from "../src/tiles/frame.ts";
import { splitB3dm } from "../src/tiles/content.ts";

const near = (a: ArrayLike<number>, b: ArrayLike<number>, eps: number) => Array.from(a).every((v, i) => Math.abs(v - b[i]) <= eps);

test("toCartesian and toCartographic take WGS 84 positions to ECEF meters and back", () => {
  assert.ok(near(toCartesian(0, 0, 0), [6378137, 0, 0], 1e-6));
  assert.ok(near(toCartesian(90, 0, 10), [0, 6378147, 0], 1e-6));
  assert.ok(near(toCartesian(0, 90, 0), [0, 0, 6356752.3142451793], 1e-6));
  const back = toCartographic(toCartesian(139.7671, 35.6812, 123.4))!;
  assert.ok(near(back, [139.7671, 35.6812, 123.4], 1e-8));
  assert.equal(toCartographic([0, 0, 0]), undefined);
});

test("eastNorthUp is the local frame at a point: east, north, up and the origin", () => {
  const m = eastNorthUp(toCartesian(0, 0, 0));
  assert.ok(near(m, [0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 6378137, 0, 0, 1], 1e-12));
  const pole = eastNorthUp([0, 0, 6356752.3]);
  assert.ok(near(pole.subarray(0, 12), [0, 1, 0, 0, -1, 0, 0, 0, 0, 0, 1, 0], 0));
});

test("boundingVolume reads boxes (transformed), regions and spheres; distances and plane tests", () => {
  const t = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 100, 0, 0, 1];
  const box = boundingVolume({ box: [0, 0, 0, 10, 0, 0, 0, 20, 0, 0, 0, 30] }, t);
  assert.deepEqual(box.center, [100, 0, 0]);
  assert.equal(distanceSquaredTo(box, [100, 0, 0]), 0);
  assert.equal(distanceSquaredTo(box, [115, 0, 0]), 25);
  const sphere = boundingVolume({ sphere: [0, 0, 0, 5] }, [2, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
  assert.ok("radius" in sphere && sphere.radius === 10);
  assert.equal(distanceSquaredTo(sphere, [13, 0, 0]), 9);
  const plane = planeFromPointNormal([0, 0, 0], [1, 0, 0]);
  assert.equal(intersectPlane(sphere, plane), INTERSECTING);
  assert.equal(intersectPlane(box, plane), INSIDE);
  assert.equal(intersectPlane(boundingVolume({ sphere: [-20, 0, 0, 5] }, t.map((v, i) => (i === 12 ? 0 : v))), plane), OUTSIDE);
  assert.equal(visibilityWithPlaneMask([plane], sphere, MASK_INSIDE), MASK_INSIDE);
  assert.equal(visibilityWithPlaneMask([plane], boundingVolume({ sphere: [-20, 0, 0, 5] }, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]), 0x7fffffff), MASK_OUTSIDE);
  const region = boundingVolume({ region: [0, 0, 0.001, 0.001, 0, 100] }, t);
  // Up from the center (half way between the corners, below the surface's arc) to the top.
  assert.ok("halfAxes" in region && Math.abs(region.halfAxes[2][0] - 51.6) < 0.1);
  assert.throws(() => boundingVolume({}, t), /box, region or sphere/);
});

/** A frame looking straight down at `x` meters along +X, the frustum wide open. */
const frame = (x: number): FrameState => ({
  position: [x, 0, 0], direction: [-1, 0, 0], up: [0, 0, 1],
  planes: [planeFromPointNormal([x - 1, 0, 0], [-1, 0, 0])], height: 600, sseDenominator: 1.15,
});

const tileset = {
  asset: { version: "1.0" },
  root: {
    boundingVolume: { sphere: [0, 0, 0, 10] }, geometricError: 100, refine: "replace", content: { uri: "root.glb" },
    children: [
      { boundingVolume: { sphere: [0, 5, 0, 5] }, geometricError: 0, content: { uri: "a.glb" } },
      { boundingVolume: { sphere: [0, -5, 0, 5] }, geometricError: 0, content: { uri: "b.glb" } },
    ],
  },
};

test("Traversal selects the root from afar and its loaded children up close (REPLACE)", () => {
  const root = buildTree(tileset, "http://x/t/tileset.json");
  assert.equal(root.contentUrl, "http://x/t/root.glb");
  assert.equal(root.refine, "REPLACE");
  assert.equal(root.children[0].refine, "REPLACE");
  const t = new Traversal(8);
  t.traverse(root, frame(1e6));
  assert.deepEqual([...t.requested.keys()], ["r"]);
  root.state = "ready";
  t.traverse(root, frame(1e6));
  assert.deepEqual([...t.selected.keys()], ["r"]);
  // Up close: the root stays drawn until both children are loaded, asked for nearest first and one
  // at a time, as loaders.gl stops at the first child not loaded.
  t.traverse(root, frame(50));
  assert.deepEqual([...t.selected.keys()], ["r"]);
  const first = [...t.requested.keys()];
  assert.equal(first.length, 1);
  root.children.find((c) => c.path === first[0])!.state = "ready";
  t.traverse(root, frame(50));
  // The loaded child is drawn over the root meanwhile, as loaders.gl draws it.
  assert.deepEqual([...t.selected.keys()].sort(), ["r", first[0]]);
  assert.equal(t.requested.size, 1);
  for (const c of root.children) c.state = "ready";
  t.traverse(root, frame(50));
  assert.deepEqual([...t.selected.keys()].sort(), ["r/0", "r/1"]);
});

test("buildTree refuses what is not a 3D Tiles tileset and hangs external tilesets under their tile", () => {
  assert.throws(() => buildTree({ asset: { version: "2.0" }, root: {} }, "http://x/"), /3D Tiles 0\.0, 1\.0 or 1\.1/);
  assert.throws(() => buildTree({ asset: { version: "1.0" } }, "http://x/"), /no root/);
  const root = buildTree(tileset, "http://x/t/tileset.json");
  const sub = buildTree(tileset, "http://x/t/sub/tileset.json", root.children[0]);
  assert.equal(sub.path, "r/0/t");
  assert.equal(sub.contentUrl, "http://x/t/sub/root.glb");
  assert.equal(root.children[0].children[0], sub);
});

/** A binary subtree file of `json` and `bin`. */
function subtreeFile(json: object, bin: Uint8Array): Uint8Array {
  const text = new TextEncoder().encode(JSON.stringify(json));
  const out = new Uint8Array(24 + text.length + bin.length);
  const v = new DataView(out.buffer);
  v.setUint32(0, 0x74627573, true);
  v.setUint32(4, 1, true);
  v.setUint32(8, text.length, true);
  v.setUint32(16, bin.length, true);
  out.set(text, 24);
  out.set(bin, 24 + text.length);
  return out;
}

test("readSubtree reads bitstreams and constants; expandImplicit splits regions per level", async () => {
  // Two levels of a quadtree: the root and children 0 and 3; content on the root and child 3.
  const bin = new Uint8Array([0b10011, 0b10001]);
  const json = { buffers: [{ byteLength: 2 }], bufferViews: [{ buffer: 0, byteOffset: 0, byteLength: 1 }, { buffer: 0, byteOffset: 1, byteLength: 1 }], tileAvailability: { bitstream: 0 }, contentAvailability: [{ bitstream: 1 }], childSubtreeAvailability: { constant: 0 } };
  const file = subtreeFile(json, bin);
  const s = await readSubtree(file, async () => new Uint8Array());
  assert.ok("bits" in s.tile && s.tile.bits[0] === 0b10011);
  assert.deepEqual(s.childSubtrees, { constant: false });
  const header = {
    boundingVolume: { region: [0, 0, 1, 1, 0, 10] }, geometricError: 64, content: { uri: "c/{level}/{x}/{y}.glb" },
    implicitTiling: { subdivisionScheme: "QUADTREE", subtreeLevels: 2, availableLevels: 2, subtrees: { uri: "s/{level}/{x}/{y}.subtree" } },
  };
  const loaded: string[] = [];
  const expanded = await expandImplicit(header, "http://x/t/tileset.json", "REPLACE", async (url) => {
    loaded.push(url);
    return file;
  });
  assert.deepEqual(loaded, ["http://x/t/s/0/0/0.subtree"]);
  assert.equal(expanded.content.uri, "http://x/t/c/0/0/0.glb");
  assert.equal(expanded.children.length, 1);
  const child = expanded.children[0];
  assert.deepEqual(child.boundingVolume.region, [0.5, 0.5, 1, 1, 0, 10]);
  assert.equal(child.geometricError, 32);
  assert.equal(child.content.uri, "http://x/t/c/1/1/1.glb");
  await assert.rejects(readSubtree(subtreeFile({}, new Uint8Array()).subarray(0, 30).map((v, i) => (i === 4 ? 2 : v)), async () => new Uint8Array()), /version 1/);
});

test("invert inverts 4x4 matrices; frameState finds the eye and the view from a Mercator matrix", () => {
  const m = [2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4, 0, 1, 2, 3, 1];
  assert.ok(near(invert(m)!, [0.5, 0, 0, 0, 0, 1 / 3, 0, 0, 0, 0, 0.25, 0, -0.5, -2 / 3, -0.75, 1], 1e-15));
  assert.equal(invert(new Array(16).fill(0)), null);
  // An orthographic-free perspective looking down -z at Mercator (0.5, 0.5) from height 0.001.
  const f = 1 / Math.tan(Math.PI / 6);
  const [n, far] = [0.0001, 0.01];
  const proj = [f, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + n) / (n - far), -1, 0, 0, (2 * far * n) / (n - far), 0];
  const view = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -0.5, -0.5, -0.001, 1];
  const mul = (a: number[], b: number[]) => Array.from({ length: 16 }, (_, i) => [0, 1, 2, 3].reduce((s, k) => s + a[k * 4 + (i % 4)] * b[Math.floor(i / 4) * 4 + k], 0));
  const state = frameState(mul(proj, view), 600)!;
  assert.equal(state.planes.length, 6);
  const eye = toCartographic(state.position)!;
  assert.ok(Math.abs(eye[0]) < 1e-9 && Math.abs(eye[1]) < 1e-9);
  assert.ok(Math.abs(eye[2] - 0.001 * 2 * Math.PI * 6378137) < 1e-3);
  // Looking down: the direction points into the Earth.
  assert.ok(state.direction[0] < -0.999);
});

test("splitB3dm reads the feature and batch tables and refuses broken headers", () => {
  const ft = new TextEncoder().encode('{"BATCH_LENGTH":2,"RTC_CENTER":[1,2,3]}');
  const bt = new TextEncoder().encode('{"id":[5,6]}');
  const glb = new Uint8Array([9, 9]);
  const bytes = new Uint8Array(28 + ft.length + bt.length + glb.length);
  const v = new DataView(bytes.buffer);
  [0x6d643362, 1, bytes.length, ft.length, 0, bt.length, 0].forEach((x, i) => v.setUint32(i * 4, x, true));
  bytes.set(ft, 28);
  bytes.set(bt, 28 + ft.length);
  bytes.set(glb, 28 + ft.length + bt.length);
  const b = splitB3dm(bytes)!;
  assert.deepEqual([b.rtc, b.batchLength, b.batchTable, [...b.glb]], [[1, 2, 3], 2, { id: [5, 6] }, [9, 9]]);
  assert.equal(splitB3dm(new Uint8Array([1, 2, 3, 4])), null);
  v.setUint32(12, 1 << 20, true);
  assert.throws(() => splitB3dm(bytes), /run past the file/);
  v.setUint32(4, 2, true);
  assert.throws(() => splitB3dm(bytes), /version 1/);
});
