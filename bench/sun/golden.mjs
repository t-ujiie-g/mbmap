// npm/src/sun.ts vs suncalc 2.1.1's getPosition (Object.is) on seeded dates 1900-2100 and places (poles,
// date line), and sunDirection vs CesiumJS 1.146.0's Simon1994PlanetaryPositions in east, north, up, within
// TOLERANCE degrees. Usage: node sun/golden.mjs [--per-month=N]; writes bench/results/sun-golden.json.
import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { getPosition } from "suncalc";
import { Cartesian3, JulianDate, Matrix3, Simon1994PlanetaryPositions, Transforms } from "cesium";
import { sunDirection, sunPosition } from "../../npm/src/sun.ts";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const PER_MONTH = Number(arg("per-month", 12));
const TOLERANCE = 0.05;
const DEG = 180 / Math.PI;

// Mulberry32: the same cases on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(20);
const between = (a, b) => a + (b - a) * rand();

const FIXED_PLACES = [[0, 90], [0, -90], [123.4, 90], [-77, -90], [180, 0], [-180, 0], [180, 64.8], [-179.999, -16.5], [0, 0], [139.77, 35.68]];
const cases = [];
for (let year = 1900; year <= 2100; year++) {
  for (let month = 0; month < 12; month++) {
    for (let k = 0; k < PER_MONTH; k++) {
      const date = new Date(Date.UTC(year, month, 1) + Math.floor(between(0, 28 * 86400000)));
      const place = k < 2 ? FIXED_PLACES[Math.floor(rand() * FIXED_PLACES.length)] : [between(-180, 180), Math.asin(between(-1, 1)) * DEG];
      cases.push({ date, lng: place[0], lat: place[1] });
    }
  }
}

let identical = 0;
const differ = [];
for (const { date, lng, lat } of cases) {
  const a = getPosition(date, lat, lng);
  const b = sunPosition(date, lng, lat);
  if (Object.is(a.azimuth, b.azimuth) && Object.is(a.altitude, b.altitude)) identical++;
  else if (differ.length < 10) differ.push({ date: date.toISOString(), lng, lat, suncalc: a, mbmap: b });
}

// Cesium's IAU 2006 XYS samples (1975-2050) loaded from its assets, as preloadIcrfFixed would fetch.
const XYS = path.join(ROOT, "bench/node_modules/cesium/Build/Cesium/Assets/IAU2006_XYS");
for (const name of await readdir(XYS)) {
  const chunk = Number(/_(\d+)\.json$/.exec(name)?.[1]);
  if (Number.isInteger(chunk)) Transforms.iau2006XysData._updateChunkData(chunk, JSON.parse(await readFile(path.join(XYS, name), "utf8")));
}

// suncalc's refraction (Meeus 16.4, clamped at the horizon), put on Cesium's geometric altitude.
const refract = (h) => h + 0.0002967 / Math.tan(Math.max(h, 0) + 0.00312536 / (Math.max(h, 0) + 0.08901179));

// The sun in east, north, up at the place: the basis of the geodetic normal, which at the poles is
// the limit suncalc's azimuth takes there (north along the meridian lng + 180°).
function cesiumDirection(date, lng, lat) {
  const jd = JulianDate.fromDate(date);
  const icrfToFixed = Transforms.computeIcrfToFixedMatrix(jd);
  if (!icrfToFixed) return null;
  const sun = Matrix3.multiplyByVector(icrfToFixed, Simon1994PlanetaryPositions.computeSunPositionInEarthInertialFrame(jd), new Cartesian3());
  const v = Cartesian3.subtract(sun, Cartesian3.fromDegrees(lng, lat, 0), new Cartesian3());
  const [l, p] = [lng / DEG, lat / DEG];
  const east = -Math.sin(l) * v.x + Math.cos(l) * v.y;
  const north = -Math.sin(p) * Math.cos(l) * v.x - Math.sin(p) * Math.sin(l) * v.y + Math.cos(p) * v.z;
  const up = Math.cos(p) * Math.cos(l) * v.x + Math.cos(p) * Math.sin(l) * v.y + Math.sin(p) * v.z;
  const h = refract(Math.atan2(up, Math.hypot(east, north)));
  const a = Math.atan2(east, north);
  return [Math.cos(h) * Math.sin(a), Math.cos(h) * Math.cos(a), Math.sin(h)];
}

const angle = (u, v) => {
  const cross = Math.hypot(u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]);
  return Math.atan2(cross, u[0] * v[0] + u[1] * v[1] + u[2] * v[2]) * DEG;
};

const angles = [];
let worst = null;
let outside = 0;
for (const { date, lng, lat } of cases) {
  const c = cesiumDirection(date, lng, lat);
  if (!c) {
    outside++;
    continue;
  }
  const d = angle(sunDirection(date, lng, lat), c);
  angles.push(d);
  if (!worst || d > worst.degrees) worst = { date: date.toISOString(), lng, lat, degrees: d };
}
angles.sort((a, b) => a - b);
const q = (f) => angles[Math.min(angles.length - 1, Math.floor(f * angles.length))];
const cesium = {
  compared: angles.length,
  outsideXysData: outside,
  toleranceDegrees: TOLERANCE,
  degrees: { median: q(0.5), p95: q(0.95), p99: q(0.99), max: angles.at(-1) },
  worst,
};

const ok = identical === cases.length && cesium.degrees.max <= TOLERANCE;
console.log(`suncalc getPosition: ${identical}/${cases.length} identical`);
for (const d of differ) console.log("  differ", JSON.stringify(d));
console.log(`Cesium Simon1994 direction: ${angles.length} compared (${outside} outside its XYS data), median ${q(0.5).toFixed(5)}°, p99 ${q(0.99).toFixed(5)}°, max ${cesium.degrees.max.toFixed(5)}° (tolerance ${TOLERANCE}°)`);
const env = { node: process.version, suncalc: "2.1.1", cesium: "1.146.0", eop: "none (UT1 = UTC)" };
await writeFile(path.join(ROOT, "bench/results/sun-golden.json"), `${JSON.stringify({ env, cases: cases.length, suncalc: { identical, differ }, cesium, ok }, null, 2)}\n`);
if (!ok) process.exit(1);
