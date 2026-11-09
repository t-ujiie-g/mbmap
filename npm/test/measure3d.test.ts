import assert from "node:assert/strict";
import test from "node:test";
import { ecef, measure3d, type Position3d } from "../src/measure3d.ts";

const near = (a: number, b: number, d = 1e-6) => assert.ok(Math.abs(a - b) <= d, `${a} vs ${b}`);
// Meters of one degree of longitude and of latitude at Tokyo Station on WGS 84 (rounded to 0.1 mm per degree).
const LAT = 35.6812;
const lngMeters = (Math.PI / 180) * 6378137 * Math.cos(LAT * (Math.PI / 180)) / Math.sqrt(1 - 0.0066943799901413165 * Math.sin(LAT * (Math.PI / 180)) ** 2);

test("ecef puts the equator at the semi-major axis and the pole at the semi-minor one", () => {
  assert.deepEqual(ecef([0, 0, 0]), [6378137, 0, 0]);
  near(ecef([0, 90, 0])[2], 6356752.314245179, 1e-6);
  near(ecef([90, 0, 10])[1], 6378147, 1e-6);
});

test("measure3d gives slant, horizontal and vertical distances", () => {
  const up = measure3d([[139.7671, LAT, 0], [139.7671, LAT, 100]]);
  near(up.length, 100);
  near(up.horizontal, 0);
  assert.equal(up.vertical, 100);
  // 30 m east and 40 m up: a 50 m slant.
  const dx = 30 / lngMeters;
  const slope = measure3d([[139.7671, LAT, 10], [139.7671 + dx, LAT, 50]]);
  near(slope.length, 50, 1e-3);
  near(slope.horizontal, 30, 1e-3);
  assert.equal(slope.vertical, 40);
  assert.deepEqual(slope.distances.length, 2);
});

test("measure3d gives a facade's area and a footprint's", () => {
  const dx = 20 / lngMeters;
  const facade: Position3d[] = [[139.7671, LAT, 0], [139.7671 + dx, LAT, 0], [139.7671 + dx, LAT, 10], [139.7671, LAT, 10]];
  const f = measure3d(facade, { closed: true });
  near(f.area, 200, 0.01);
  near(f.horizontalArea, 0, 0.01);
  near(f.length, 60, 1e-3);
  const dy = 10 / 110952.5;
  const roof: Position3d[] = [[139.7671, LAT, 30], [139.7671 + dx, LAT, 30], [139.7671 + dx, LAT + dy, 30], [139.7671, LAT + dy, 30]];
  const r = measure3d(roof, { closed: true });
  near(r.area, r.horizontalArea, 0.01);
  near(r.area, 200, 0.5);
  assert.equal(measure3d(roof).area, 0);
});
