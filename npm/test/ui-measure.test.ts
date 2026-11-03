import assert from "node:assert/strict";
import test from "node:test";
import { boundsAround, distanceTo, roundNumber } from "../src/ui/measure.ts";

test("roundNumber: 1, 2, 3 or 5 times a power of ten, at most the number", () => {
  assert.deepEqual([1, 2.5, 4, 7, 9.99, 12, 480, 3100, 0.34, 0.0072].map(roundNumber), [1, 2, 3, 5, 5, 10, 300, 3000, 0.3, 0.007]);
});

test("distanceTo: great-circle meters on MapLibre's sphere", () => {
  // MapLibre's documented example: New York to Los Angeles.
  const d = distanceTo({ lng: -74.0060, lat: 40.7128 }, { lng: -118.2437, lat: 34.0522 });
  assert.ok(Math.abs(d - 3935751.690893987) < 1e-6, String(d));
  // acos near 1 rounds, as in MapLibre: the same point is under a meter apart.
  assert.ok(distanceTo({ lng: 139, lat: 35 }, { lng: 139, lat: 35 }) < 1);
});

test("boundsAround: a radius in degrees of latitude, widened in longitude by the latitude", () => {
  const [w, s, e, n] = boundsAround({ lng: 0, lat: 60 }, 40075017 / 360);
  assert.ok(Math.abs(n - 61) < 1e-12 && Math.abs(s - 59) < 1e-12);
  assert.ok(Math.abs(e - 2) < 1e-9 && Math.abs(w + 2) < 1e-9);
});
