// Writes the pack test's 3D Tiles (bench/npm/pages/tiles/set/): blocks near Tokyo Station as b3dm with
// RTC_CENTER and a batch table, glTF +Y up as 3D Tiles 1.0 wants; a root of one block per quadrant
// refined (REPLACE) into four tiles of eight to sixteen blocks each, the first a cmpt that adds a row
// of instanced "trees" (i3dm, east-north-up). Beside it (points/) a pnts of colored points with a row
// per point in its batch table, ADD-refined by a glTF of points. Usage: node tiles/synthetic.mjs
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { Document, NodeIO } from "@gltf-transform/core";
import { Ellipsoid } from "@math.gl/geospatial";
import { ROOT } from "../lib/root.mjs";

const DIR = path.join(ROOT, "bench/npm/pages/tiles/set");
const CENTER = [139.7671, 35.6812];
const rad = Math.PI / 180;

// Mulberry32: the same blocks on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(43);

/** A b3dm of `blocks` ([lng, lat, width m, depth m, height m, color]) around ECEF `rtc`. */
async function b3dm(blocks, rtc) {
  const doc = new Document();
  const buf = doc.createBuffer();
  const mesh = doc.createMesh();
  blocks.forEach(([lng, lat, w, d, h, color], batch) => {
    const base = Ellipsoid.WGS84.cartographicToCartesian([lng, lat, 0]);
    const m = Ellipsoid.WGS84.eastNorthUpToFixedFrame(base);
    const enu = (e, n, u) => [0, 1, 2].map((k) => base[k] + m[k] * e + m[4 + k] * n + m[8 + k] * u - rtc[k]);
    // ECEF axes to glTF's +Y up: (x, y, z) to (x, z, -y).
    const gltf = ([x, y, z]) => [x, z, -y];
    const pos = [];
    const nor = [];
    const idx = [];
    const faces = [
      [[1, 0, 0], [[1, -1, 0], [1, 1, 0], [1, 1, 1], [1, -1, 1]]],
      [[-1, 0, 0], [[-1, 1, 0], [-1, -1, 0], [-1, -1, 1], [-1, 1, 1]]],
      [[0, 1, 0], [[1, 1, 0], [-1, 1, 0], [-1, 1, 1], [1, 1, 1]]],
      [[0, -1, 0], [[-1, -1, 0], [1, -1, 0], [1, -1, 1], [-1, -1, 1]]],
      [[0, 0, 1], [[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]]],
    ];
    for (const [n, corners] of faces) {
      const at = pos.length / 3;
      const normal = gltf(enu(...n).map((v, k) => v + rtc[k] - base[k]));
      for (const [x, y, z] of corners) {
        pos.push(...gltf(enu((x * w) / 2, (y * d) / 2, z * h)));
        nor.push(...normal);
      }
      idx.push(at, at + 1, at + 2, at, at + 2, at + 3);
    }
    const acc = (type, array) => doc.createAccessor().setType(type).setArray(array).setBuffer(buf);
    mesh.addPrimitive(doc.createPrimitive()
      .setAttribute("POSITION", acc("VEC3", new Float32Array(pos)))
      .setAttribute("NORMAL", acc("VEC3", new Float32Array(nor)))
      .setAttribute("_BATCHID", acc("SCALAR", new Float32Array(pos.length / 3).fill(batch)))
      .setIndices(acc("SCALAR", new Uint16Array(idx)))
      .setMaterial(doc.createMaterial().setBaseColorFactor(color)));
  });
  doc.createScene().addChild(doc.createNode().setMesh(mesh));
  const glb = await new NodeIO().writeBinary(doc);
  const pad = (s) => s + " ".repeat((8 - (s.length % 8)) % 8);
  const ft = new TextEncoder().encode(pad(JSON.stringify({ BATCH_LENGTH: blocks.length, RTC_CENTER: rtc })));
  const bt = new TextEncoder().encode(pad(JSON.stringify({ height: blocks.map((b) => b[4]) })));
  const out = new Uint8Array(28 + ft.length + bt.length + glb.length);
  const v = new DataView(out.buffer);
  [0x6d643362, 1, out.length, ft.length, 0, bt.length, 0].forEach((x, i) => v.setUint32(i * 4, x, true));
  out.set(ft, 28);
  out.set(bt, 28 + ft.length);
  out.set(glb, 28 + ft.length + bt.length);
  return out;
}

/** An i3dm of a 6 m green box at each of `points` ([lng, lat]), upright (EAST_NORTH_UP), around ECEF `rtc`. */
async function i3dm(points, rtc) {
  const doc = new Document();
  const buf = doc.createBuffer();
  const pos = [];
  const nor = [];
  const idx = [];
  for (const [n, corners] of [
    [[1, 0, 0], [[1, 0, -1], [1, 0, 1], [1, 2, 1], [1, 2, -1]]],
    [[-1, 0, 0], [[-1, 0, 1], [-1, 0, -1], [-1, 2, -1], [-1, 2, 1]]],
    [[0, 0, 1], [[1, 0, 1], [-1, 0, 1], [-1, 2, 1], [1, 2, 1]]],
    [[0, 0, -1], [[-1, 0, -1], [1, 0, -1], [1, 2, -1], [-1, 2, -1]]],
    [[0, 1, 0], [[-1, 2, -1], [1, 2, -1], [1, 2, 1], [-1, 2, 1]]],
  ]) {
    const at = pos.length / 3;
    for (const c of corners) {
      pos.push(...c.map((v) => v * 3));
      nor.push(...n);
    }
    idx.push(at, at + 1, at + 2, at, at + 2, at + 3);
  }
  const acc = (type, array) => doc.createAccessor().setType(type).setArray(array).setBuffer(buf);
  doc.createScene().addChild(doc.createNode().setMesh(doc.createMesh().addPrimitive(doc.createPrimitive()
    .setAttribute("POSITION", acc("VEC3", new Float32Array(pos)))
    .setAttribute("NORMAL", acc("VEC3", new Float32Array(nor)))
    .setIndices(acc("SCALAR", new Uint16Array(idx)))
    .setMaterial(doc.createMaterial().setBaseColorFactor([0.2, 0.6, 0.25, 1])))));
  const glb = await new NodeIO().writeBinary(doc);
  const positions = new Float32Array(points.flatMap(([lng, lat]) => Ellipsoid.WGS84.cartographicToCartesian([lng, lat, 0]).map((v, k) => v - rtc[k])));
  const pad = (s) => s + " ".repeat((8 - (s.length % 8)) % 8);
  const ft = new TextEncoder().encode(pad(JSON.stringify({ INSTANCES_LENGTH: points.length, RTC_CENTER: rtc, EAST_NORTH_UP: true, POSITION: { byteOffset: 0 } })));
  const ftBin = new Uint8Array(positions.buffer);
  const bt = new TextEncoder().encode(pad(JSON.stringify({ kind: points.map(() => "tree") })));
  const out = new Uint8Array(32 + ft.length + ftBin.length + bt.length + glb.length);
  const v = new DataView(out.buffer);
  [0x6d643369, 1, out.length, ft.length, ftBin.length, bt.length, 0, 1].forEach((x, i) => v.setUint32(i * 4, x, true));
  out.set(ft, 32);
  out.set(ftBin, 32 + ft.length);
  out.set(bt, 32 + ft.length + ftBin.length);
  out.set(glb, 32 + ft.length + ftBin.length + bt.length);
  return out;
}

/** A cmpt of `tiles` (each padded to 8 bytes as the specification asks). */
function cmpt(tiles) {
  const padded = tiles.map((t) => {
    const p = new Uint8Array((t.length + 7) & ~7);
    p.set(t);
    new DataView(p.buffer).setUint32(8, p.length, true);
    return p;
  });
  const out = new Uint8Array(16 + padded.reduce((n, t) => n + t.length, 0));
  const v = new DataView(out.buffer);
  [0x74706d63, 1, out.length, tiles.length].forEach((x, i) => v.setUint32(i * 4, x, true));
  let at = 16;
  for (const t of padded) {
    out.set(t, at);
    at += t.length;
  }
  return out;
}

const colors = [[0.85, 0.35, 0.25, 1], [0.3, 0.55, 0.85, 1], [0.35, 0.7, 0.4, 1], [0.9, 0.75, 0.3, 1]];
const region = (w, s, e, n, h) => [w * rad, s * rad, e * rad, n * rad, 0, h];
const span = 0.004;
const quadrants = [[-1, -1], [1, -1], [-1, 1], [1, 1]].map(([qx, qy], q) => {
  const [w, s] = [CENTER[0] + (qx < 0 ? -span : 0), CENTER[1] + (qy < 0 ? -span : 0)];
  const blocks = [];
  const n = 8 + Math.floor(rand() * 9);
  for (let i = 0; i < n; i++) {
    blocks.push([w + span * (0.1 + 0.8 * rand()), s + span * (0.1 + 0.8 * rand()), 20 + 30 * rand(), 20 + 30 * rand(), 20 + 160 * rand(), colors[q]]);
  }
  return { w, s, e: w + span, n: s + span, blocks, color: colors[q] };
});
await mkdir(DIR, { recursive: true });
const ecef = (lng, lat) => [...Ellipsoid.WGS84.cartographicToCartesian([lng, lat, 0])];
for (const [q, quad] of quadrants.entries()) {
  const rtc = ecef(quad.w + span / 2, quad.s + span / 2);
  const blocks = await b3dm(quad.blocks, rtc);
  if (q > 0) {
    await writeFile(path.join(DIR, `q${q}.b3dm`), blocks);
    continue;
  }
  const trees = Array.from({ length: 12 }, (_, i) => [quad.w + span * (0.05 + 0.075 * i), quad.s + span * 0.03]);
  await writeFile(path.join(DIR, "q0.cmpt"), cmpt([blocks, await i3dm(trees, rtc)]));
}
const coarse = quadrants.map((quad) => [quad.w + span / 2, quad.s + span / 2, span * 70000, span * 70000, 60, quad.color]);
await writeFile(path.join(DIR, "root.b3dm"), await b3dm(coarse, ecef(...CENTER)));
const tileset = {
  asset: { version: "1.0" },
  geometricError: 500,
  root: {
    boundingVolume: { region: region(CENTER[0] - span, CENTER[1] - span, CENTER[0] + span, CENTER[1] + span, 200) },
    geometricError: 120,
    refine: "REPLACE",
    content: { uri: "root.b3dm" },
    children: quadrants.map((quad, q) => ({ boundingVolume: { region: region(quad.w, quad.s, quad.e, quad.n, 200) }, geometricError: 0, content: { uri: q === 0 ? "q0.cmpt" : `q${q}.b3dm` } })),
  },
};
await writeFile(path.join(DIR, "tileset.json"), JSON.stringify(tileset, null, 1) + "\n");

// Points: a 40 m red and blue checkerboard of points near Tokyo Station (pnts, `kind` per point) and a
// green ring of glTF points around it (a child, ADD).
const POINTS_DIR = path.join(DIR, "../points");
await mkdir(POINTS_DIR, { recursive: true });
const PLACE = [139.7655, 35.6795];
const prtc = ecef(...PLACE);
const grid = [];
for (let i = 0; i < 60; i++) for (let j = 0; j < 60; j++) grid.push([i - 30, j - 30, 2 + ((i * 7 + j * 3) % 5)]);
const local = (e, n, u) => {
  const m = Ellipsoid.WGS84.eastNorthUpToFixedFrame(prtc);
  return [0, 1, 2].map((k) => m[k] * e + m[4 + k] * n + m[8 + k] * u);
};
const ppos = new Float32Array(grid.flatMap(([e, n, u]) => local(e, n, u)));
const prgb = new Uint8Array(grid.flatMap(([e, n]) => (Math.floor((e + 30) / 10) + Math.floor((n + 30) / 10)) % 2 ? [220, 40, 40] : [40, 70, 220]));
const pkind = grid.map(([e, n]) => ((Math.floor((e + 30) / 10) + Math.floor((n + 30) / 10)) % 2 ? "red" : "blue"));
{
  const pad = (s) => s + " ".repeat((8 - (s.length % 8)) % 8);
  const ftBin = new Uint8Array(ppos.byteLength + prgb.byteLength + ((8 - (prgb.byteLength % 8)) % 8));
  ftBin.set(new Uint8Array(ppos.buffer), 0);
  ftBin.set(prgb, ppos.byteLength);
  const ft = new TextEncoder().encode(pad(JSON.stringify({ POINTS_LENGTH: grid.length, RTC_CENTER: prtc, POSITION: { byteOffset: 0 }, RGB: { byteOffset: ppos.byteLength } })));
  const bt = new TextEncoder().encode(pad(JSON.stringify({ kind: pkind })));
  const out = new Uint8Array(28 + ft.length + ftBin.length + bt.length);
  [0x73746e70, 1, out.length, ft.length, ftBin.length, bt.length, 0].forEach((x, i) => new DataView(out.buffer).setUint32(i * 4, x, true));
  out.set(ft, 28);
  out.set(ftBin, 28 + ft.length);
  out.set(bt, 28 + ft.length + ftBin.length);
  await writeFile(path.join(POINTS_DIR, "grid.pnts"), out);
}
{
  const doc = new Document();
  const buf = doc.createBuffer();
  const ring = Array.from({ length: 360 }, (_, i) => [45 * Math.cos((i * Math.PI) / 180), 45 * Math.sin((i * Math.PI) / 180), 3]);
  // glTF is +Y up: (east, north, up) as (east, up, -north); the tile's transform is the place's frame.
  const acc = (type, array) => doc.createAccessor().setType(type).setArray(array).setBuffer(buf);
  const prim = doc.createPrimitive()
    .setMode(0)
    .setAttribute("POSITION", acc("VEC3", new Float32Array(ring.flatMap(([e, n, u]) => [e, u, -n]))))
    .setAttribute("COLOR_0", acc("VEC4", new Uint8Array(ring.flatMap(() => [30, 170, 60, 255]))).setNormalized(true));
  doc.createScene().addChild(doc.createNode().setMesh(doc.createMesh().addPrimitive(prim)));
  await writeFile(path.join(POINTS_DIR, "ring.glb"), await new NodeIO().writeBinary(doc));
}
const pbox = region(PLACE[0] - 0.0006, PLACE[1] - 0.0006, PLACE[0] + 0.0006, PLACE[1] + 0.0006, 20);
await writeFile(path.join(POINTS_DIR, "tileset.json"), JSON.stringify({
  asset: { version: "1.1" },
  geometricError: 100,
  root: {
    boundingVolume: { region: pbox },
    geometricError: 50,
    refine: "ADD",
    content: { uri: "grid.pnts" },
    children: [{ boundingVolume: { region: pbox }, geometricError: 0, content: { uri: "ring.glb" }, transform: [...Ellipsoid.WGS84.eastNorthUpToFixedFrame(prtc)] }],
  },
}, null, 1) + "\n");
