import assert from "node:assert/strict";
import test from "node:test";
import { nearestIndex, profileStats } from "../src/ui/elevation.ts";

test("profileStats: range, ascent and descent, skipping samples without data", () => {
  assert.deepEqual(profileStats([10, 30, 20, NaN, 25, 5]), { min: 5, max: 30, gain: 25, loss: 30 });
  assert.deepEqual(profileStats([7]), { min: 7, max: 7, gain: 0, loss: 0 });
  assert.deepEqual(profileStats([NaN, NaN]), { min: NaN, max: NaN, gain: 0, loss: 0 });
  assert.deepEqual(profileStats([]), { min: NaN, max: NaN, gain: 0, loss: 0 });
});

test("nearestIndex: the nearest distance, the lower one on a tie", () => {
  const d = [0, 10, 20, 40];
  assert.equal(nearestIndex(d, -5), 0);
  assert.equal(nearestIndex(d, 14), 1);
  assert.equal(nearestIndex(d, 15), 1);
  assert.equal(nearestIndex(d, 16), 2);
  assert.equal(nearestIndex(d, 100), 3);
  assert.equal(nearestIndex([], 1), -1);
  assert.equal(nearestIndex(d, NaN), -1);
});
