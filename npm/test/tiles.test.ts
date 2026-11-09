import assert from "node:assert/strict";
import test from "node:test";
import { boundingVolume, distanceSquaredTo, eastNorthUp, intersectPlane, INSIDE, INTERSECTING, MASK_INSIDE, MASK_OUTSIDE, OUTSIDE, planeFromPointNormal, toCartesian, toCartographic, visibilityWithPlaneMask } from "../src/tiles/geo.ts";
import { buildTree, lineageHas, Traversal, type FrameState } from "../src/tiles/tileset.ts";
import { expandImplicit, readSubtree } from "../src/tiles/implicit.ts";
import { frameState, invert } from "../src/tiles/frame.ts";
import { readTileContent, splitB3dm } from "../src/tiles/content.ts";

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
  for (const bad of [{ subtreeLevels: 0 }, { subtreeLevels: 11 }, { availableLevels: 32 }, { subtreeLevels: 1.5 }]) {
    const h = { ...header, implicitTiling: { ...header.implicitTiling, ...bad } };
    await assert.rejects(expandImplicit(h, "http://x/t/tileset.json", "REPLACE", async () => file), /subtreeLevels from 1 to 10/);
  }
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
  assert.deepEqual([b.rtc, b.batchLength, b.batchTable, [...b.batchBinary], [...b.glb]], [[1, 2, 3], 2, { id: [5, 6] }, [], [9, 9]]);
  assert.equal(splitB3dm(new Uint8Array([1, 2, 3, 4])), null);
  v.setUint32(12, 1 << 20, true);
  assert.throws(() => splitB3dm(bytes), /run past the file/);
  v.setUint32(4, 2, true);
  assert.throws(() => splitB3dm(bytes), /version 1/);
});

const words = (bytes: Uint8Array, ...xs: number[]) => xs.forEach((x, i) => new DataView(bytes.buffer, bytes.byteOffset).setUint32(i * 4, x, true));
const GLTF = new TextEncoder().encode('{"asset":{"version":"2.0"},"buffers":[{"uri":"b.bin","byteLength":4}]}');
const loadAny = async () => new Uint8Array(4);

/** An i3dm of a feature table (JSON padded to 8, then `bin`) and `body` after it, gltfFormat `format`. */
function i3dm(ft: object, bin: Uint8Array, body: Uint8Array, format = 1): Uint8Array {
  let text = JSON.stringify(ft);
  while (text.length % 8) text += " ";
  const out = new Uint8Array(32 + text.length + bin.length + body.length);
  words(out, 0x6d643369, 1, out.length, text.length, bin.length, 0, 0, format);
  out.set(new TextEncoder().encode(text), 32);
  out.set(bin, 32 + text.length);
  out.set(body, 32 + text.length + bin.length);
  return out;
}

const f32Bytes = (xs: number[]) => new Uint8Array(new Float32Array(xs).buffer);

test("readTileContent reads an i3dm's instances: positions, RTC_CENTER, SCALE and BATCH_ID", async () => {
  const bin = new Uint8Array(32);
  bin.set(f32Bytes([1, 2, 3, 4, 5, 6]), 0);
  bin.set(f32Bytes([2, 0.5]), 24);
  const ft = { INSTANCES_LENGTH: 2, RTC_CENTER: [100, 200, 300], POSITION: { byteOffset: 0 }, SCALE: { byteOffset: 24 }, BATCH_ID: [7, 3] };
  const c = await readTileContent(i3dm(ft, bin, GLTF), loadAny);
  assert.equal(c.kind, "i3dm");
  assert.equal(c.rtc, null);
  assert.equal(c.batchLength, 2);
  assert.deepEqual([...c.instances!.batchIds], [7, 3]);
  assert.deepEqual([...c.instances!.matrices], [2, 0, 0, 0, 0, 2, 0, 0, 0, 0, 2, 0, 101, 202, 303, 1, 0.5, 0, 0, 0, 0, 0.5, 0, 0, 0, 0, 0.5, 0, 104, 205, 306, 1]);
});

test("i3dm orientations: quantized positions, NORMAL_UP and NORMAL_RIGHT, oct-encoded normals, EAST_NORTH_UP", async () => {
  const q = new Uint8Array(new Uint16Array([0, 65535, 0, 0]).buffer);
  const quantized = await readTileContent(i3dm({ INSTANCES_LENGTH: 1, POSITION_QUANTIZED: { byteOffset: 0 }, QUANTIZED_VOLUME_OFFSET: [10, 20, 30], QUANTIZED_VOLUME_SCALE: [5, 6, 7] }, q, GLTF), loadAny);
  assert.deepEqual([...quantized.instances!.matrices.subarray(12, 15)], [10, 26, 30]);
  // Right +Y and up +Z make forward +X.
  const normals = new Uint8Array(40);
  normals.set(f32Bytes([0, 0, 0, 0, 0, 1, 0, 1, 0]));
  const turned = await readTileContent(i3dm({ INSTANCES_LENGTH: 1, POSITION: { byteOffset: 0 }, NORMAL_UP: { byteOffset: 12 }, NORMAL_RIGHT: { byteOffset: 24 } }, normals, GLTF), loadAny);
  assert.ok(near(turned.instances!.matrices.subarray(0, 12), [0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0], 1e-15));
  // Oct (65535, 32768) is about +X and (32768, 65535) about +Y.
  const oct = new Uint8Array(24);
  oct.set(new Uint8Array(new Uint16Array([32768, 65535, 65535, 32768]).buffer), 12);
  const decoded = await readTileContent(i3dm({ INSTANCES_LENGTH: 1, POSITION: { byteOffset: 0 }, NORMAL_UP_OCT32P: { byteOffset: 12 }, NORMAL_RIGHT_OCT32P: { byteOffset: 16 } }, oct, GLTF), loadAny);
  assert.ok(near(decoded.instances!.matrices.subarray(0, 12), [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0], 1e-4));
  const enu = await readTileContent(i3dm({ INSTANCES_LENGTH: 1, POSITION: [6378137, 0, 0], EAST_NORTH_UP: true }, new Uint8Array(0), GLTF), loadAny);
  assert.ok(near(enu.instances!.matrices, [0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 6378137, 0, 0, 1], 1e-12));
});

test("an i3dm's glTF by URI loads beside it, and broken i3dm are refused", async () => {
  const asked: string[] = [];
  const load = async (u: string) => {
    asked.push(u);
    return u === "models/a.gltf" ? GLTF : new Uint8Array(4);
  };
  const byUri = i3dm({ INSTANCES_LENGTH: 1, POSITION: [0, 0, 0] }, new Uint8Array(0), new TextEncoder().encode("models/a.gltf\0\0\0"), 0);
  await readTileContent(byUri, load);
  assert.deepEqual(asked, ["models/a.gltf", "models/b.bin"]);
  const ok = i3dm({ INSTANCES_LENGTH: 1, POSITION: [0, 0, 0] }, new Uint8Array(0), GLTF);
  await assert.rejects(readTileContent(ok.subarray(0, 40), load), /cut short/);
  await assert.rejects(readTileContent(i3dm({ INSTANCES_LENGTH: 2e6, POSITION: [0, 0, 0] }, new Uint8Array(0), GLTF), load), /more than 1000000/);
  await assert.rejects(readTileContent(i3dm({ INSTANCES_LENGTH: 1, POSITION: { byteOffset: 4 } }, new Uint8Array(8), GLTF), load), /runs past the feature table/);
  await assert.rejects(readTileContent(i3dm({ INSTANCES_LENGTH: 1 }, new Uint8Array(0), GLTF), load), /neither POSITION/);
  await assert.rejects(readTileContent(i3dm({ INSTANCES_LENGTH: 1, POSITION: [0, 0, 0] }, new Uint8Array(0), GLTF, 2), load), /gltfFormat/);
  await assert.rejects(readTileContent(i3dm({ INSTANCES_LENGTH: 1, POSITION: [0, 0, 0] }, new Uint8Array(0), new Uint8Array(0)), load), /no glTF/);
});

/** A cmpt of `tiles` back to back. */
/** A pnts of feature table `ft` and `bin`, and batch table `bt` (JSON) when given. */
function pnts(ft: object, bin: Uint8Array, bt?: object): Uint8Array {
  const pad = (t: string) => t + " ".repeat((8 - (t.length % 8)) % 8);
  const f = new TextEncoder().encode(pad(JSON.stringify(ft)));
  const b = bt ? new TextEncoder().encode(pad(JSON.stringify(bt))) : new Uint8Array(0);
  const out = new Uint8Array(28 + f.length + bin.length + b.length);
  words(out, 0x73746e70, 1, out.length, f.length, bin.length, b.length, 0);
  out.set(f, 28);
  out.set(bin, 28 + f.length);
  out.set(b, 28 + f.length + bin.length);
  return out;
}

const u16Bytes = (xs: number[]) => new Uint8Array(new Uint16Array(xs).buffer);

test("readTileContent reads a pnts as one POINTS primitive: positions, RGB, normals, RTC_CENTER", async () => {
  const bin = new Uint8Array(32);
  bin.set(f32Bytes([1, 2, 3, 4, 5, 6]), 0);
  bin.set([255, 0, 0, 0, 128, 255], 24);
  const c = await readTileContent(pnts({ POINTS_LENGTH: 2, RTC_CENTER: [10, 20, 30], POSITION: { byteOffset: 0 }, RGB: { byteOffset: 24 }, NORMAL: [0, 0, 1, 0, 1, 0] }, bin), loadAny);
  assert.equal(c.kind, "pnts");
  assert.deepEqual(c.rtc, [10, 20, 30]);
  const [p] = c.model.primitives;
  assert.equal(p.mode, 0);
  assert.equal(p.indices, undefined);
  assert.deepEqual([...p.attributes.POSITION.data], [1, 2, 3, 4, 5, 6]);
  assert.deepEqual({ data: [...p.attributes.COLOR_0.data], size: p.attributes.COLOR_0.size, normalized: p.attributes.COLOR_0.normalized }, { data: [255, 0, 0, 0, 128, 255], size: 3, normalized: true });
  assert.deepEqual([...p.attributes.NORMAL.data], [0, 0, 1, 0, 1, 0]);
  assert.equal(p.attributes._BATCHID, undefined);
  assert.deepEqual(c.model.materials[0], { color: [1, 1, 1, 1], alphaMode: "OPAQUE", alphaCutoff: 0.5, doubleSided: true, unlit: false });
});

test("readTileContent dequantizes pnts positions into RTC, decodes RGB565, oct normals and CONSTANT_RGBA", async () => {
  const bin = new Uint8Array(24);
  bin.set(u16Bytes([0, 65535, 0, 65535, 0, 65535]), 0);
  bin.set(u16Bytes([0xf800, 0x07e0]), 12);
  bin.set([255, 128, 128, 128], 16);
  const ft = { POINTS_LENGTH: 2, RTC_CENTER: [1, 1, 1], QUANTIZED_VOLUME_OFFSET: [100, 200, 300], QUANTIZED_VOLUME_SCALE: [10, 20, 30], POSITION_QUANTIZED: { byteOffset: 0 }, RGB565: { byteOffset: 12 }, NORMAL_OCT16P: { byteOffset: 16 }, CONSTANT_RGBA: [255, 255, 255, 51] };
  const c = await readTileContent(pnts(ft, bin), loadAny);
  assert.deepEqual(c.rtc, [101, 201, 301]);
  const [p] = c.model.primitives;
  assert.deepEqual([...p.attributes.POSITION.data], [0, 20, 0, 10, 0, 30]);
  assert.deepEqual([...p.attributes.COLOR_0.data], [255, 0, 0, 0, 255, 0]);
  assert.ok(near(p.attributes.NORMAL.data, [1, 0, 0, 0, 0, 1], 1e-2));
  assert.equal(c.model.materials[0].alphaMode, "BLEND");
  assert.ok(near(c.model.materials[0].color, [1, 1, 1, 0.2], 1e-9));
  await assert.rejects(readTileContent(pnts({ ...ft, QUANTIZED_VOLUME_SCALE: undefined }, bin), loadAny), /needs QUANTIZED_VOLUME_OFFSET/);
});

test("readTileContent gives pnts points their batch ids: BATCH_ID, else one row per point", async () => {
  const bin = new Uint8Array(16);
  bin.set(f32Bytes([0, 0, 0]), 0);
  bin.set(u16Bytes([7]), 12);
  const byId = await readTileContent(pnts({ POINTS_LENGTH: 1, BATCH_LENGTH: 8, POSITION: { byteOffset: 0 }, BATCH_ID: { byteOffset: 12 } }, bin, { kind: Array(8).fill("a") }), loadAny);
  assert.deepEqual([...byId.model.primitives[0].attributes._BATCHID.data], [7]);
  assert.equal(byId.batchLength, 8);
  const perPoint = await readTileContent(pnts({ POINTS_LENGTH: 2, POSITION: [0, 0, 0, 1, 1, 1] }, new Uint8Array(0), { kind: ["a", "b"] }), loadAny);
  assert.deepEqual([...perPoint.model.primitives[0].attributes._BATCHID.data], [0, 1]);
  assert.equal(perPoint.batchLength, 2);
  assert.deepEqual(perPoint.batchTable, { kind: ["a", "b"] });
});

test("readTileContent decodes a pnts' Draco semantics and batch properties through `draco`", async () => {
  const bin = new Uint8Array(8);
  const ft = { POINTS_LENGTH: 2, POSITION: { byteOffset: 0 }, extensions: { "3DTILES_draco_point_compression": { properties: { POSITION: 0, RGB: 1 }, byteOffset: 0, byteLength: 8 } } };
  const bt = { extensions: { "3DTILES_draco_point_compression": { properties: { height: 2 } } } };
  const calls: number[] = [];
  const draco = (bytes: Uint8Array) => {
    calls.push(bytes.length);
    const attributes = new Map([
      [0, { data: new Float32Array([1, 2, 3, 4, 5, 6]), size: 3, type: 5126, normalized: false }],
      [1, { data: new Uint8Array([1, 2, 3, 4, 5, 6]), size: 3, type: 5121, normalized: true }],
      [2, { data: new Float32Array([7.5, 8.5]), size: 1, type: 5126, normalized: false }],
    ]);
    return { indices: new Uint32Array(0), attributes };
  };
  const c = await readTileContent(pnts(ft, bin, bt), loadAny, undefined, draco);
  assert.deepEqual(calls, [8]);
  const [p] = c.model.primitives;
  assert.deepEqual([...p.attributes.POSITION.data], [1, 2, 3, 4, 5, 6]);
  assert.deepEqual([...p.attributes.COLOR_0.data], [1, 2, 3, 4, 5, 6]);
  assert.deepEqual(c.batchTable, { height: [7.5, 8.5] });
  await assert.rejects(readTileContent(pnts(ft, bin, bt), loadAny), /Draco compression is not available/);
  const past = { ...ft, extensions: { "3DTILES_draco_point_compression": { properties: { POSITION: 0 }, byteOffset: 4, byteLength: 8 } } };
  await assert.rejects(readTileContent(pnts(past, bin), loadAny, undefined, draco), /runs past the feature table/);
  const missing = { ...ft, extensions: { "3DTILES_draco_point_compression": { properties: { POSITION: 9 }, byteOffset: 0, byteLength: 8 } } };
  await assert.rejects(readTileContent(pnts(missing, bin), loadAny, undefined, draco), /has no attribute 9/);
});

test("readTileContent refuses pnts without POINTS_LENGTH or positions, or with too many points", async () => {
  await assert.rejects(readTileContent(pnts({}, new Uint8Array(0)), loadAny), /no POINTS_LENGTH/);
  await assert.rejects(readTileContent(pnts({ POINTS_LENGTH: 1 }, new Uint8Array(0)), loadAny), /neither POSITION nor POSITION_QUANTIZED/);
  await assert.rejects(readTileContent(pnts({ POINTS_LENGTH: 1e9, POSITION: { byteOffset: 0 } }, new Uint8Array(0)), loadAny), /more than/);
  await assert.rejects(readTileContent(pnts({ POINTS_LENGTH: 2, POSITION: { byteOffset: 0 } }, new Uint8Array(12)), loadAny), /runs past the feature table/);
});

function cmpt(tiles: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(16 + tiles.reduce((a, t) => a + t.length, 0));
  words(out, 0x74706d63, 1, out.length, tiles.length);
  let at = 16;
  for (const t of tiles) {
    out.set(t, at);
    at += t.length;
  }
  return out;
}

test("readTileContent of a cmpt gives its inner tiles as parts, nested ones flattened", async () => {
  const b3dm = new Uint8Array(28 + GLTF.length);
  words(b3dm, 0x6d643362, 1, b3dm.length, 0, 0, 0, 0);
  b3dm.set(GLTF, 28);
  const points = pnts({ POINTS_LENGTH: 1, POSITION: { byteOffset: 0 } }, f32Bytes([1, 2, 3]));
  const one = i3dm({ INSTANCES_LENGTH: 1, POSITION: [0, 0, 0] }, new Uint8Array(0), GLTF);
  const c = await readTileContent(cmpt([b3dm, cmpt([points, one]), one]), loadAny);
  assert.equal(c.kind, "cmpt");
  assert.deepEqual(c.model, { primitives: [], materials: [], images: [] });
  assert.deepEqual(c.parts.map((p) => p.kind), ["b3dm", "pnts", "i3dm", "i3dm"]);
  let deep = b3dm;
  for (let i = 0; i < 10; i++) deep = cmpt([deep]);
  await assert.rejects(readTileContent(deep, loadAny), /nest deeper/);
  const empty = cmpt([b3dm]);
  words(empty.subarray(16 + 8), 0);
  await assert.rejects(readTileContent(empty, loadAny), /runs past the file/);
  await assert.rejects(readTileContent(cmpt([b3dm]).subarray(0, 20), loadAny), /cut short/);
  const unknown = cmpt([b3dm]);
  words(unknown.subarray(16), 0x12345678);
  await assert.rejects(readTileContent(unknown, loadAny), /neither b3dm/);
});

test("lineageHas finds a tile among its ancestors", () => {
  const root = buildTree({ asset: { version: "1.0" }, root: { geometricError: 1, boundingVolume: { sphere: [0, 0, 0, 1] }, content: { uri: "a.json" }, children: [{ geometricError: 0, boundingVolume: { sphere: [0, 0, 0, 1] } }] } }, "http://x/t.json");
  const child = root.children[0];
  assert.ok(lineageHas(child, (t) => t.contentUrl === "http://x/a.json"));
  assert.ok(!lineageHas(child, (t) => t.contentUrl === "http://x/b.json"));
  assert.ok(!lineageHas(null, () => true));
});
