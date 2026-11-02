import assert from "node:assert/strict";
import test from "node:test";
import { LngLatBounds, fitArray, flyArray, limitsArray, targetArray, toPadding } from "../src/camera.ts";

test("LngLatBounds converts the shapes MapLibre takes", () => {
  for (const b of [[[139, 35], [140, 36]], [139, 35, 140, 36], [{ lng: 139, lat: 35 }, { lng: 140, lat: 36 }]] as const) {
    const c = LngLatBounds.convert(b as never);
    assert.deepEqual([c.getWest(), c.getSouth(), c.getEast(), c.getNorth()], [139, 35, 140, 36]);
  }
  const b = new LngLatBounds(139, 35, 140, 36);
  assert.equal(LngLatBounds.convert(b), b);
  assert.deepEqual(b.getCenter(), { lng: 139.5, lat: 35.5 });
  assert.deepEqual(b.toArray(), [[139, 35], [140, 36]]);
  assert.deepEqual([b.getSouthWest(), b.getNorthEast()], [{ lng: 139, lat: 35 }, { lng: 140, lat: 36 }]);
});

test("move targets leave out what is not given and refuse non-finite values", () => {
  const t = targetArray({ center: [139.7, 35.6], zoom: 14, offset: { x: 5, y: -5 } });
  assert.deepEqual(t.slice(0, 3), [139.7, 35.6, 14]);
  assert.ok(t.slice(3, 7).every(Number.isNaN));
  assert.deepEqual(t.slice(7), [5, -5]);
  assert.deepEqual(targetArray({ around: { lng: 1, lat: 2 }, bearing: 30 }).slice(3, 7), [30, NaN, 1, 2]);
  assert.throws(() => targetArray({ zoom: Infinity }), /finite/);
  assert.deepEqual(flyArray({ curve: 2, maxDuration: 100 }).map((v) => (Number.isNaN(v) ? null : v)), [null, 2, null, null, 100, null]);
});

test("padding, limits and fits take the engine's layout", () => {
  assert.deepEqual(toPadding(10), [10, 10, 10, 10]);
  assert.deepEqual(toPadding({ left: 5 }), [0, 0, 0, 5]);
  assert.deepEqual(toPadding(undefined), [0, 0, 0, 0]);
  const none = limitsArray({ minZoom: 1, maxZoom: 20, minPitch: 0, maxPitch: 60, maxBounds: null });
  assert.deepEqual(none.slice(0, 4), [1, 20, 0, 60]);
  assert.ok(Number.isNaN(none[4]));
  assert.deepEqual(limitsArray({ minZoom: 0, maxZoom: 22, minPitch: 0, maxPitch: 85, maxBounds: new LngLatBounds(1, 2, 3, 4) }).slice(4), [1, 2, 3, 4]);
  const fit = fitArray(new LngLatBounds(1, 2, 3, 4), { padding: 20, bearing: 45, offset: [1, 2], maxZoom: 9 });
  assert.deepEqual(fit, [1, 2, 3, 4, 45, 20, 20, 20, 20, 1, 2, 9]);
});
