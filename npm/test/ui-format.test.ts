import assert from "node:assert/strict";
import test from "node:test";
import { dms, formatDegrees, formatDms, utmZone } from "../src/ui/format.ts";

test("dms: degrees, minutes and rounded seconds, carrying 60 seconds over", () => {
  assert.equal(dms(35.6812, "N", "S"), "35°40′52.3″N");
  assert.equal(dms(-0.5, "N", "S", 0), "0°30′00″S");
  assert.equal(dms(139.99999, "E", "W"), "140°00′00.0″E");
  assert.equal(formatDms({ lng: 139.7671, lat: 35.6812 }), "35°40′52.3″N 139°46′01.6″E");
});

test("formatDegrees: latitude first", () => {
  assert.equal(formatDegrees({ lng: 139.7671, lat: 35.6812 }, 3), "35.681, 139.767");
});

test("utmZone: six-degree zones from 180°W, north and south", () => {
  assert.deepEqual(utmZone({ lng: 139.7671, lat: 35.6812 }), { zone: 54, north: true, epsg: 32654 });
  assert.deepEqual(utmZone({ lng: -70.6, lat: -33.4 }), { zone: 19, north: false, epsg: 32719 });
  assert.equal(utmZone({ lng: 180, lat: 1 }).zone, 1);
  assert.equal(utmZone({ lng: 179.99, lat: 1 }).zone, 60);
});
