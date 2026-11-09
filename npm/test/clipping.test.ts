import assert from "node:assert/strict";
import test from "node:test";
import { mercatorMeters, packClipping } from "../src/clipping.ts";

test("packClipping gives the origin, flags, edge, unit planes, then rings in meters at the origin", () => {
  const n = packClipping({ origin: [139.7671, 35.6812], planes: [[0, 2, 0, 4]], unionClippingRegions: true, edgeWidth: 3, edgeColor: [1, 0.5, 0], polygons: [[[139.7671, 35.6812], [139.7681, 35.6812], [139.7671, 35.6822]]], inverse: true });
  assert.deepEqual(n.slice(0, 14), [139.7671, 35.6812, 0, 1, 1, 3, 1, 0.5, 0, 1, 0, 1, 0, 2]);
  assert.deepEqual(n.slice(14, 16), [1, 3]);
  const m = mercatorMeters(35.6812);
  assert.deepEqual(n.slice(16, 18), [0, 0]);
  assert.ok(Math.abs(n[18] - (0.001 / 360) * m) < 1e-9 && n[19] === 0);
  // 0.001° north is about 111 m at the map's scale there (a little more on Mercator than on the ground).
  assert.ok(n[20] === 0 && n[21] > 111 && n[21] < 112);
});

test("packClipping refuses too many planes, rings or points, and numbers that are not finite", () => {
  const plane: [number, number, number, number] = [1, 0, 0, 0];
  assert.throws(() => packClipping({ origin: [0, 0], planes: new Array(17).fill(plane) }), /at most 16 planes/);
  assert.throws(() => packClipping({ origin: [0, 0], polygons: [new Array(65).fill([0, 0])] }), /64 points/);
  assert.throws(() => packClipping({ origin: [0, Number.NaN], planes: [plane] }), /finite/);
  assert.deepEqual(packClipping({ origin: [1, 2, 3] }).slice(0, 11), [1, 2, 3, 0, 0, 0, 1, 1, 1, 0, 0]);
});
