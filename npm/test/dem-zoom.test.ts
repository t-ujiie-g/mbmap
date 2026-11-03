import assert from "node:assert/strict";
import test from "node:test";
import { demZoom } from "../src/dem-zoom.ts";

test("demZoom: the deepest zoom whose tiles fit one grid", () => {
  // Tokyo Station to Shinjuku (about 6 km): 16 tiles a side reach zoom 14.
  assert.equal(demZoom([139.70, 35.68, 139.77, 35.69], 14), 14);
  assert.equal(demZoom([139.70, 35.68, 139.77, 35.69], 12), 12);
  // Tokyo to Osaka: zoom 10 (13 columns), not 11 (25).
  assert.equal(demZoom([135.4959, 34.7025, 139.7671, 35.6812], 14), 10);
  assert.equal(demZoom([135.4959, 34.7025, 139.7671, 35.6812], 14, 512), 9);
  assert.equal(demZoom([-180, -85, 180, 85], 14), 4);
});

test("demZoom: zoom capped at 24, tile sizes outside 256-4096 refused", () => {
  assert.equal(demZoom([139.767, 35.681, 139.7671, 35.6811], 1e7), 24);
  assert.throws(() => demZoom([0, 0, 1, 1], 14, 1), /tileSize/);
  assert.throws(() => demZoom([0, 0, 1, 1], 14, NaN), /tileSize/);
});
