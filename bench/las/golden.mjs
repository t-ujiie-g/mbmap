// mbmap/3d's LAS reader (npm/src/model/las.ts) vs @loaders.gl/las 4.5.4: synthetic files of every
// version and point format (its laz-rs parser, which reads 1.4 and formats 0 to 10; its default laz-perf
// one too where it reads them), PDAL's sample files, and hostile copies refused.
// Usage: node las/golden.mjs; writes bench/results/las-golden.json.
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { LASLoader } from "@loaders.gl/las";
import { Matrix4 } from "@math.gl/core";
import { Ellipsoid } from "@math.gl/geospatial";
import proj4 from "proj4";
import { parseLAS as parseLazRs } from "../node_modules/@loaders.gl/las/dist/lib/laz-rs-wasm/parse-las.js";
import { readLas } from "../../npm/src/model/las.ts";
import { parseProjString } from "../../npm/src/projstring.ts";
import { ROOT } from "../lib/root.mjs";
import { geoKeys, RGB_AT, writeLas, wktRecord } from "./write.mjs";

// Mulberry32: the same files on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(20);
const int = (lo, hi) => lo + Math.floor(rand() * (hi - lo + 1));

const FORMATS = [[0, 1], [0, 1], [0, 1, 2, 3], [0, 1, 2, 3, 4, 5], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]];
const SCALES = [
  { scale: [0.01, 0.01, 0.01], offset: [0, 0, 0], range: 1 << 20 },
  { scale: [0.001, 0.001, 0.001], offset: [-123456.789, 3987654.321, 12.5], range: 2 ** 31 - 1 },
  { scale: [1e-7, 1e-7, 0.001], offset: [139, 35, 0], range: 1e7 },
  { scale: [0.25, 1 / 3, 0.1], offset: [500000, 0, -1000.125], range: 2 ** 31 - 1 },
];

function points(n, format, range, wideColors) {
  return Array.from({ length: n }, () => ({
    x: int(-range, range),
    y: int(-range, range),
    z: int(-range, range),
    intensity: int(0, 65535),
    returns: int(0, 255),
    classification: format >= 6 ? int(0, 255) : int(0, 31),
    flags: int(0, 7),
    rgb: [0, 0, 0].map(() => int(0, wideColors ? 65535 : 255)),
  }));
}

const results = [];
let failed = 0;
const record = (r) => {
  results.push(r);
  if (!r.same) failed++;
};

/** The first difference between readLas and a loaders.gl parse of `bytes`, or null. */
function differs(cloud, mesh, legacyClasses) {
  const h = mesh.loaderData;
  const header = [
    ["version", cloud.version, h.versionAsString ?? cloud.version],
    ["pointFormat", cloud.pointFormat, h.pointsFormatId],
    ["recordLength", cloud.recordLength, h.pointsStructSize],
    ["count", cloud.count, h.pointsCount],
    ["kept", cloud.kept, mesh.header.vertexCount],
    ["scale", cloud.scale.join(), h.scale.join()],
    ["offset", cloud.offset.join(), h.offset.join()],
    ["min", cloud.min.join(), h.mins.join()],
    ["max", cloud.max.join(), h.maxs.join()],
  ];
  for (const [name, a, b] of header) if (a !== b) return `${name}: ${a} vs ${b}`;
  const at = mesh.attributes;
  const pos = at.POSITION.value;
  if (pos.length !== cloud.positions.length) return "positions length";
  for (let i = 0; i < pos.length; i++) if (!Object.is(pos[i], cloud.positions[i])) return `position ${i}: ${cloud.positions[i]} vs ${pos[i]}`;
  for (let i = 0; i < cloud.kept; i++) {
    if (at.intensity.value[i] !== cloud.intensity[i]) return `intensity ${i}`;
    const cls = legacyClasses ? at.classification.value[i] & 31 : at.classification.value[i];
    if (cls !== cloud.classification[i]) return `classification ${i}: ${cloud.classification[i]} vs ${cls}`;
  }
  if (!at.COLOR_0 !== !cloud.colors) return "colors present on one side";
  if (cloud.colors) {
    for (let i = 0; i < cloud.kept; i++) {
      for (let c = 0; c < 3; c++) if (at.COLOR_0.value[i * 4 + c] !== cloud.colors[i * 3 + c]) return `color ${i}.${c}: ${cloud.colors[i * 3 + c]} vs ${at.COLOR_0.value[i * 4 + c]}`;
    }
  }
  return null;
}

/** readLas vs loaders.gl's laz-rs parser, and its default laz-perf one for LAS 1.0 to 1.3 formats 0 to 3. */
function compare(name, bytes, maxPoints = 1e9) {
  const cloud = readLas(bytes, maxPoints);
  const skip = cloud.count > maxPoints ? Math.ceil(cloud.count / maxPoints) : 1;
  const options = { las: { fp64: true, colorDepth: "auto", skip } };
  const legacy = cloud.pointFormat < 6;
  const parsers = [["laz-rs", (b) => parseLazRs(b, options)]];
  if (cloud.version !== "1.4" && cloud.pointFormat <= 3) parsers.push(["laz-perf", (b) => LASLoader.parseSync(b, options)]);
  for (const [parser, parse] of parsers) {
    const diff = differs(cloud, parse(bytes.slice().buffer), legacy);
    record({ case: name, parser, points: cloud.kept, same: diff === null, ...(diff ? { diff } : {}) });
  }
  return cloud;
}

for (let minor = 0; minor <= 4; minor++) {
  for (const format of FORMATS[minor]) {
    SCALES.forEach(({ scale, offset, range }, s) => {
      const wide = s % 2 === 0;
      const extra = s % 2 === 1 ? 13 : 0;
      const bytes = writeLas({ minor, format, scale, offset, extra, points: points(int(1, 600), format, range, wide) });
      const colors = RGB_AT[format] !== undefined ? (wide ? ", 16-bit colors" : ", 8-bit colors in 16") : "";
      compare(`1.${minor} format ${format}, scale ${s}${extra ? `, ${extra} extra bytes` : ""}${colors}`, bytes);
    });
  }
}

// Thinned: every k-th point, as loaders.gl's `skip`.
for (const [minor, format, n, maxPoints] of [[2, 3, 500, 167], [4, 7, 500, 72], [4, 10, 1000, 999], [3, 1, 10, 1]]) {
  compare(`1.${minor} format ${format}, ${n} points thinned to ${maxPoints}`, writeLas({ minor, format, points: points(n, format, 1 << 24, true) }), maxPoints);
}

// The CRS, which loaders.gl does not read: as written.
const wkt = 'PROJCS["JGD2011 / Japan Plane Rectangular CS IX",GEOGCS["JGD2011",AUTHORITY["EPSG","6668"]],UNIT["metre",1],AUTHORITY["EPSG","6677"]]';
for (const [name, args, want] of [
  ["GeoTIFF keys, projected", { minor: 2, vlrs: [geoKeys([[2048, 6668], [3072, 6677]])] }, { epsg: 6677 }],
  ["GeoTIFF keys, geographic", { minor: 3, vlrs: [geoKeys([[2048, 4326], [4096, 5703]])] }, { epsg: 4326 }],
  ["WKT in an EVLR, its bit set", { minor: 4, evlrs: [wktRecord(wkt)], globalEncoding: 16 }, { epsg: 6677, wkt }],
  ["WKT and keys, WKT bit clear", { minor: 4, vlrs: [geoKeys([[3072, 2451]]), wktRecord(wkt)] }, { epsg: 2451 }],
]) {
  const cloud = compare(`crs: ${name}`, writeLas({ format: 1, points: points(3, 1, 1000, false), ...args }));
  const same = JSON.stringify(cloud.crs) === JSON.stringify(want);
  record({ case: `crs: ${name}`, same, crs: cloud.crs });
}

// PDAL's sample files (BSD license), fetched once and pinned.
const PDAL_URL = "https://raw.githubusercontent.com/PDAL/PDAL/2.8.0/test/data/las/";
const PDAL = {
  "simple.las": ["a0570ef57b685b77a6d3e3992cbdfeecdb2c3065d3780bbeaba490818258b734", undefined],
  "test_epsg_4326.las": ["2e0c03a459eba46489917013fa9184bd843450ec3d63a214b5de2253f746797c", 4326],
  "test_epsg_4047.las": ["2ba2bbed82f086a4fb47b972ca772cf3f86f54f374742f14b620bff6ea35f94c", 4047],
  "test_utm17.las": ["0691dab458c9862a230adef9330b724b904b1fa6ac4eab8d49f9c24a22df845b", undefined],
  "extrabytes.las": ["b8daf5a96114ac86c42fff13e07abdc736e00e1eb34188506a6895b1126ed75b", undefined],
  "4_6.las": ["bc45fd1a72fa37ddc02fdfd2e30cda0e4cfe80111d1e0ac98d9bb0969268c65b", undefined],
};
const PDAL_DIR = path.join(ROOT, "bench/fixtures/pdal-las");
let pdalFiles = 0;
for (const [name, [sha256, epsg]] of Object.entries(PDAL)) {
  const file = path.join(PDAL_DIR, name);
  let bytes = existsSync(file) ? new Uint8Array(await readFile(file)) : null;
  if (!bytes) {
    try {
      const res = await fetch(PDAL_URL + name);
      if (res.ok) bytes = new Uint8Array(await res.arrayBuffer());
    } catch {}
    if (!bytes) {
      console.log(`${name}: not fetched (set NODE_USE_ENV_PROXY=1 behind a proxy); skipped`);
      continue;
    }
  }
  const hash = createHash("sha256").update(bytes).digest("hex");
  if (hash !== sha256) throw new Error(`${name}: sha256 ${hash} differs`);
  await mkdir(PDAL_DIR, { recursive: true });
  await writeFile(file, bytes);
  pdalFiles++;
  const cloud = compare(`PDAL ${name}`, bytes);
  compare(`PDAL ${name} thinned to 100`, bytes, 100);
  record({ case: `PDAL ${name} crs`, same: epsg === undefined || cloud.crs?.epsg === epsg, crs: cloud.crs });
}

const edit = (bytes, f) => {
  const b = bytes.slice();
  f(new DataView(b.buffer), b);
  return b;
};

// The 3D worker's `las` op (npm/dist/3d-worker.js with proj.wasm and prjwkt.js, run here) vs proj4js
// 2.22.0 and math.gl's east-north-up frame: positions within 5 mm, bounds within 1e-8°.
const DIST = path.join(ROOT, "npm/dist");
const dataUrl = (bytes, type) => `data:${type};base64,${Buffer.from(bytes).toString("base64")}`;
globalThis.onmessage = null;
const answers = new Map();
globalThis.postMessage = (m) => answers.get(m.id)?.(m);
await import(pathToFileURL(path.join(DIST, "3d-worker.js")).href);
const worker = globalThis.onmessage;
worker({ data: { type: "init", wasm: "unused:", proj: dataUrl(await readFile(path.join(DIST, "proj.wasm")), "application/wasm"), prj: pathToFileURL(path.join(DIST, "prjwkt.js")).href } });
let nextId = 0;
const call = (bytes, maxPoints, crs) =>
  new Promise((resolve) => {
    const id = nextId++;
    answers.set(id, resolve);
    worker({ data: { type: "call", id, op: "las", url: dataUrl(bytes, "application/octet-stream"), maxPoints, ...(crs === undefined ? {} : { crs }) } });
  });

/** How far the worker's answer for `bytes` lies from proj4js (`from`, a PROJ string or "EPSG:4326") and math.gl, or why it differs. */
async function workerDiffers(bytes, maxPoints, crs, from) {
  const { value, error } = await call(bytes, maxPoints, crs);
  if (error) return { diff: error };
  const cloud = readLas(bytes, maxPoints);
  const geo = [];
  for (let i = 0; i < cloud.kept; i++) {
    const [lon, lat] = from === "EPSG:4326" ? [cloud.positions[i * 3], cloud.positions[i * 3 + 1]] : proj4(from, "EPSG:4326", [cloud.positions[i * 3], cloud.positions[i * 3 + 1]]);
    geo.push([lon, lat, cloud.positions[i * 3 + 2]]);
  }
  const bounds = [0, 1, 2].map((k) => Math.min(...geo.map((g) => g[k]))).concat([0, 1, 2].map((k) => Math.max(...geo.map((g) => g[k]))));
  if (value.count !== cloud.count || value.kept !== cloud.kept) return { diff: "count or kept" };
  if (bounds.some((b, i) => Math.abs(b - value.bounds[i]) > 1e-8)) return { diff: `bounds ${value.bounds} vs ${bounds}` };
  const center = [0, 1, 2].map((k) => (value.bounds[k] + value.bounds[k + 3]) / 2);
  if (center.some((c, i) => c !== value.center[i])) return { diff: "center is not the middle of the bounds" };
  const toLocal = new Matrix4(Ellipsoid.WGS84.eastNorthUpToFixedFrame(Ellipsoid.WGS84.cartographicToCartesian(center))).invert();
  let worst = 0;
  geo.forEach((g, i) => {
    const local = toLocal.transform(Ellipsoid.WGS84.cartographicToCartesian(g));
    for (let k = 0; k < 3; k++) worst = Math.max(worst, Math.abs(local[k] - value.positions[i * 3 + k]));
  });
  if (!(value.positions instanceof Float32Array) || worst > 0.005) return { diff: `positions ${worst} m off`, worst };
  const same = (a, b) => (a === null ? b === null : b !== null && a.length === b.length && a.every((x, i) => x === b[i]));
  if (!same(value.colors, cloud.colors) || !same(value.intensity, cloud.intensity) || !same(value.classification, cloud.classification)) return { diff: "attributes" };
  return { diff: null, worst };
}

const PLANE = "+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs";
const PLANE_WKT =
  'PROJCS["plane IX",GEOGCS["JGD2011",DATUM["Japanese_Geodetic_Datum_2011",SPHEROID["GRS 1980",6378137,298.257222101]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]],PROJECTION["Transverse_Mercator"],PARAMETER["latitude_of_origin",36],PARAMETER["central_meridian",139.833333333333],PARAMETER["scale_factor",0.9999],PARAMETER["false_easting",0],PARAMETER["false_northing",0],UNIT["metre",1]]';
const fixture = new Uint8Array(await readFile(path.join(ROOT, "bench/npm/pages/pointcloud/cloud.las")));
const tokyo = (args) => writeLas({ format: 2, scale: [0.001, 0.001, 0.001], offset: [-6000, -35400, 0], points: points(2000, 2, 200_000, true), ...args });
const definition = parseProjString(PLANE);
for (const [name, bytes, maxPoints, crs, from] of [
  ["pack test fixture (GeoTIFF keys 6677)", fixture, 1e6, undefined, PLANE],
  ["pack test fixture thinned to 10000", fixture, 10000, undefined, PLANE],
  ["no CRS, crs 6677 given", tokyo({ minor: 2 }), 1e6, 6677, PLANE],
  ["GeoTIFF keys 4326 overridden by a definition", tokyo({ minor: 2, vlrs: [geoKeys([[2048, 4326]])] }), 1e6, definition, PLANE],
  ["WKT without an authority (prjwkt)", tokyo({ minor: 4, vlrs: [wktRecord(PLANE_WKT)], globalEncoding: 16 }), 1e6, undefined, PLANE],
  ["compound WKT, horizontal 6677", tokyo({ minor: 4, evlrs: [wktRecord(`COMPD_CS["c",${wkt},VERT_CS["h",AUTHORITY["EPSG","6695"]]]`)], globalEncoding: 16 }), 1e6, undefined, PLANE],
  ["GeoTIFF keys 4326, no proj.wasm", writeLas({ minor: 3, format: 3, scale: [1e-7, 1e-7, 0.01], offset: [139.7, 35.6, 0], points: points(500, 3, 1e6, false), vlrs: [geoKeys([[2048, 4326]])] }), 1e6, undefined, "EPSG:4326"],
]) {
  const r = await workerDiffers(bytes, maxPoints, crs, from);
  record({ case: `worker: ${name}`, same: r.diff === null, ...r });
}
for (const [name, bytes, maxPoints, crs, want] of [
  ["no CRS anywhere", tokyo({ minor: 2 }), 1e6, undefined, /states no CRS/],
  ["LAZ", edit(fixture, (v, b) => (b[104] |= 0x80)), 1e6, undefined, /LAZ/],
  ["maxPoints 0", fixture, 0, undefined, /invalid arguments/],
  ["maxPoints past MAX_LAS_POINTS", fixture, 2e7, undefined, /invalid arguments/],
  ["crs a short definition", fixture, 1e6, new Float64Array(3), /invalid arguments/],
  ["crs a string", fixture, 1e6, "EPSG:6677", /invalid arguments/],
  ["out of reach of the CRS", tokyo({ minor: 2, offset: [1e9, 1e9, 0] }), 1e6, 6677, /out of reach/],
]) {
  const { error } = await call(bytes, maxPoints, crs);
  record({ case: `worker refuses: ${name}`, same: want.test(error ?? ""), error });
}

// Hostile copies: each refused, none taking long.
const base14 = writeLas({ minor: 4, format: 7, points: points(50, 7, 1000, true), vlrs: [geoKeys([[3072, 6677]])], evlrs: [wktRecord(wkt)] });
const base12 = writeLas({ minor: 2, format: 3, points: points(50, 3, 1000, true), vlrs: [geoKeys([[3072, 6677]])] });
const hostile = [
  ["LAZ point format bit 7", edit(base12, (v, b) => (b[104] |= 0x80))],
  ["LAZ point format bit 6", edit(base12, (v, b) => (b[104] |= 0x40))],
  ["laszip VLR", writeLas({ minor: 2, format: 0, points: points(1, 0, 10, false), vlrs: [{ userId: "laszip encoded", recordId: 22204, data: new Uint8Array(52) }] })],
  ["not LASF", edit(base12, (v, b) => (b[3] = 0x58))],
  ["version 1.5", edit(base12, (v, b) => (b[25] = 5))],
  ["version 2.0", edit(base12, (v, b) => ((b[24] = 2), (b[25] = 0)))],
  ["point format 11", edit(base12, (v, b) => (b[104] = 11))],
  ["record length shorter than the format", edit(base12, (v) => v.setUint16(105, 20, true))],
  ["header size 100", edit(base12, (v) => v.setUint16(94, 100, true))],
  ["header size 227 for 1.4", edit(base14, (v) => v.setUint16(94, 227, true))],
  ["header size past the file", edit(writeLas({ minor: 2, format: 0, points: [] }), (v) => v.setUint16(94, 4000, true))],
  ["point offset past the file", edit(base12, (v) => v.setUint32(96, 0xfffffff0, true))],
  ["point offset inside the header", edit(base12, (v) => v.setUint32(96, 10, true))],
  ["legacy count past the file", edit(base12, (v) => v.setUint32(107, 0xffffffff, true))],
  ["64-bit count past the file", edit(base14, (v) => v.setBigUint64(247, 1n << 40n, true))],
  ["64-bit count 2^63", edit(base14, (v) => v.setBigUint64(247, 1n << 63n, true))],
  ["VLR count 2^32 - 1", edit(base12, (v) => v.setUint32(100, 0xffffffff, true))],
  ["VLR count past the file", edit(base12, (v) => v.setUint32(100, 4000, true))],
  ["VLR length past the file", edit(writeLas({ minor: 2, format: 0, points: [], vlrs: [geoKeys([])] }), (v) => v.setUint16(227 + 20, 60000, true))],
  ["EVLR offset past the file", edit(base14, (v) => v.setBigUint64(235, 1n << 50n, true))],
  ["EVLR length past the file", edit(base14, (v) => v.setBigUint64(base14.length - wktRecord(wkt).data.length - 60 + 20, 1n << 62n, true))],
  ["EVLR count 2^32 - 1", edit(base14, (v) => v.setUint32(243, 0xffffffff, true))],
  ["scale NaN", edit(base12, (v) => v.setFloat64(131, NaN, true))],
  ["offset Infinity", edit(base12, (v) => v.setFloat64(171, Infinity, true))],
];
for (const bytes of [base12, base14]) {
  for (let n = 0; n < bytes.length; n += 37) hostile.push([`${bytes[25] === 4 ? "1.4" : "1.2"} cut at ${n} of ${bytes.length}`, bytes.subarray(0, n)]);
}
for (const [name, bytes] of hostile) {
  let refused = null;
  const start = performance.now();
  try {
    readLas(bytes, 1e9);
  } catch (err) {
    refused = err instanceof Error ? err.message : String(err);
  }
  const ms = performance.now() - start;
  record({ case: `hostile: ${name}`, same: refused !== null && ms < 1000, refused, ms: Math.round(ms) });
}

await mkdir(path.join(ROOT, "bench/results"), { recursive: true });
await writeFile(path.join(ROOT, "bench/results/las-golden.json"), JSON.stringify({ env: { loaders: "@loaders.gl/las 4.5.4", pdalFiles }, results }, null, 2) + "\n");
for (const r of results) if (!r.same || process.argv.includes("--verbose")) console.log(JSON.stringify(r));
console.log(`las golden: ${results.length} cases, ${pdalFiles} PDAL files, ${failed} differ`);
if (failed) process.exit(1);
