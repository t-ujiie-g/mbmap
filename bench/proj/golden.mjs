// proj vs proj4js 2.22.0: every EPSG code `Crs::from_epsg` knows and PROJ strings per projection,
// forward, inverse and CRS to CRS, js and wasm-gc; fails beyond 1 mm or 1e-8°.
// Usage: node proj/golden.mjs [--points=N]; writes bench/results/proj-golden.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import proj4 from "proj4";
import { parseProjString } from "../../npm/src/projstring.ts";
import { loadEntry } from "../lib/entry.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { ROOT } from "../lib/root.mjs";
import { arg } from "../lib/args.mjs";

const POINTS = Number(arg("points", 200));
const { mbtJs: mbt, gc } = await loadEntry(nodeFetchBytes, nodeImportJs);

// EPSG codes, as epsg.io gives their PROJ strings (proj4js has only 4326 and 3857).
const ORIGINS = [[33, 129, 30], [33, 131, 0], [36, 132, 10], [33, 133, 30], [36, 134, 20], [36, 136, 0], [36, 137, 10], [36, 138, 30], [36, 139, 50], [40, 140, 50], [44, 140, 15], [44, 142, 15], [44, 144, 15], [26, 142, 0], [26, 127, 30], [26, 124, 0], [26, 131, 0], [20, 136, 0], [26, 154, 0]];
const GRS80 = "+ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs";
const TOKYO = "+ellps=bessel +towgs84=-146.414,507.337,680.507,0,0,0,0 +units=m +no_defs";
const JAPAN = [122, 20, 154, 46];
const crss = [];
const epsg = (code, def, area) => {
  if (def) proj4.defs(`EPSG:${code}`, def);
  crss.push({ name: `EPSG:${code}`, code, area });
};
for (const code of [4612, 6668]) epsg(code, `+proj=longlat ${GRS80}`, JAPAN);
epsg(4301, `+proj=longlat ${TOKYO}`, JAPAN);
epsg(4326, null, [-180, -85, 180, 85]);
epsg(3857, null, [-180, -85, 180, 85]);
ORIGINS.forEach(([lat, deg, min], i) => {
  const lon = deg + min / 60;
  const area = [lon - 2, lat - 2, lon + 2, lat + 2];
  for (const code of [6669 + i, 2443 + i]) epsg(code, `+proj=tmerc +lat_0=${lat} +lon_0=${lon} +k=0.9999 +x_0=0 +y_0=0 ${GRS80}`, area);
  epsg(30161 + i, `+proj=tmerc +lat_0=${lat} +lon_0=${lon} +k=0.9999 +x_0=0 +y_0=0 ${TOKYO}`, area);
});
for (let zone = 1; zone <= 60; zone++) {
  const lon = zone * 6 - 183;
  epsg(32600 + zone, null, [lon - 3, 0, lon + 3, 84]);
  epsg(32700 + zone, null, [lon - 3, -80, lon + 3, 0]);
}
for (let zone = 51; zone <= 55; zone++) {
  const lon = zone * 6 - 183;
  const area = [lon - 3, 20, lon + 3, 46];
  for (const code of [6688 + zone - 51, 3097 + zone - 51]) epsg(code, `+proj=utm +zone=${zone} ${GRS80}`, area);
  epsg(3092 + zone - 51, `+proj=utm +zone=${zone} ${TOKYO}`, area);
}

// PROJ strings, one or more per projection (mostly EPSG's own). proj4js keeps
// a's length under +R_A (54003's Miller), so that case is a unit test against
// PROJ instead.
const strings = [
  ["World Mercator (3395)", "+proj=merc +lon_0=0 +k=1 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs", [-180, -80, 180, 84]],
  ["Mercator true at 35°", "+proj=merc +lat_ts=35 +lon_0=135 +datum=WGS84", [100, -60, 170, 80]],
  ["Lambert 93 (2154)", "+proj=lcc +lat_0=46.5 +lon_0=3 +lat_1=49 +lat_2=44 +x_0=700000 +y_0=6600000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs", [-5, 41, 10, 51]],
  ["NTF Lambert II, Paris meridian (27572)", "+proj=lcc +lat_1=46.8 +lat_0=46.8 +lon_0=0 +k_0=0.99987742 +x_0=600000 +y_0=2200000 +a=6378249.2 +b=6356515 +towgs84=-168,-60,320,0,0,0,0 +pm=paris +units=m +no_defs", [-5, 42, 8, 51]],
  ["California V in US feet (2229)", "+proj=lcc +lat_0=33.5 +lon_0=-118 +lat_1=35.4666666666667 +lat_2=34.0333333333333 +x_0=2000000.0001016 +y_0=500000.0001016 +datum=NAD83 +units=us-ft +no_defs", [-121, 32.5, -114, 35.8]],
  ["Conus Albers (5070)", "+proj=aea +lat_0=23 +lon_0=-96 +lat_1=29.5 +lat_2=45.5 +x_0=0 +y_0=0 +datum=NAD83 +units=m +no_defs", [-125, 24, -66, 50]],
  ["Azimuthal equidistant on Tokyo", "+proj=aeqd +lat_0=35.6812 +lon_0=139.7671 +x_0=0 +y_0=0 +datum=WGS84", [120, 20, 160, 50]],
  ["Azimuthal equidistant, north pole", "+proj=aeqd +lat_0=90 +lon_0=0 +datum=WGS84", [-180, 60, 180, 89]],
  ["Azimuthal equidistant on a sphere", "+proj=aeqd +lat_0=35 +lon_0=135 +R=6371000", [100, 0, 170, 70]],
  ["NSIDC polar stereographic north (3413)", "+proj=stere +lat_0=90 +lat_ts=70 +lon_0=-45 +k=1 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs", [-180, 60, 180, 89]],
  ["Antarctic polar stereographic (3031)", "+proj=stere +lat_0=-90 +lat_ts=-71 +lon_0=0 +k=1 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs", [-180, -89, 180, -60]],
  ["Oblique stereographic", "+proj=stere +lat_0=35 +lon_0=135 +k=0.9999 +datum=WGS84", [125, 25, 145, 45]],
  ["Stereographic on a sphere", "+proj=stere +lat_0=35 +lon_0=135 +R=6371000", [115, 15, 155, 55]],
  ["Amersfoort / RD New (28992)", "+proj=sterea +lat_0=52.1561605555556 +lon_0=5.38763888888889 +k=0.9999079 +x_0=155000 +y_0=463000 +ellps=bessel +towgs84=565.4171,50.3319,465.5524,1.9342,-1.6677,9.1019,4.0725 +units=m +no_defs", [3, 50.5, 7.5, 54]],
  ["Soldner Berlin (3068)", "+proj=cass +lat_0=52.4186482777778 +lon_0=13.6272036666667 +x_0=40000 +y_0=10000 +ellps=bessel +towgs84=598.1,73.7,418.2,0.202,0.045,-2.455,6.7 +units=m +no_defs", [13, 52.2, 13.8, 52.7]],
  ["Cassini on a sphere", "+proj=cass +lat_0=35 +lon_0=135 +R=6371000", [130, 30, 140, 40]],
  ["ETRS89 LAEA Europe (3035)", "+proj=laea +lat_0=52 +lon_0=10 +x_0=4321000 +y_0=3210000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs", [-30, 30, 40, 75]],
  ["LAEA north pole", "+proj=laea +lat_0=90 +lon_0=0 +datum=WGS84", [-180, 45, 180, 89]],
  ["LAEA on the equator", "+proj=laea +lat_0=0 +lon_0=0 +datum=WGS84", [-60, -60, 60, 60]],
  ["LAEA on a sphere", "+proj=laea +lat_0=45 +lon_0=-100 +R=6370997", [-140, 20, -60, 70]],
  ["Plate carrée (4087)", "+proj=eqc +lat_ts=0 +lat_0=0 +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs", [-180, -89, 180, 89]],
  ["Equidistant conic", "+proj=eqdc +lat_0=40 +lon_0=-96 +lat_1=20 +lat_2=60 +x_0=0 +y_0=0 +datum=NAD83", [-140, 15, -60, 70]],
  ["Sinusoidal", "+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84", [-180, -85, 180, 85]],
  ["MODIS sinusoidal", "+proj=sinu +lon_0=0 +x_0=0 +y_0=0 +R=6371007.181 +units=m", [-180, -85, 180, 85]],
  ["Eckert VI", "+proj=eck6 +lon_0=0 +R=6371000", [-180, -85, 180, 85]],
  ["Mollweide (54009)", "+proj=moll +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs", [-180, -85, 180, 85]],
  ["Robinson (54030)", "+proj=robin +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs", [-180, -85, 180, 85]],
  ["EASE-Grid 2.0 global (6933)", "+proj=cea +lat_ts=30 +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs", [-180, -85, 180, 85]],
  ["Miller", "+proj=mill +lat_0=0 +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs", [-180, -85, 180, 85]],
  ["SAD69 Brazil polyconic (29101)", "+proj=poly +lat_0=0 +lon_0=-54 +x_0=5000000 +y_0=10000000 +ellps=aust_SA +towgs84=-67.35,3.88,-38.22,0,0,0,0 +units=m +no_defs", [-74, -33, -35, 5]],
  ["Alaska zone 1, oblique Mercator (26931)", "+proj=omerc +lat_0=57 +lonc=-133.666666666667 +alpha=323.130102361111 +k=0.9999 +x_0=5000000 +y_0=-5000000 +no_uoff +gamma=323.130102361111 +datum=NAD83 +units=m +no_defs", [-141, 54, -129, 60]],
  ["Peninsular RSO (3375)", "+proj=omerc +lat_0=4 +lonc=102.25 +alpha=323.0257905 +k=0.99984 +x_0=804671 +y_0=0 +no_uoff +gamma=323.1301023611111 +ellps=GRS80 +units=m +no_defs", [99, 1, 105, 7]],
  ["Oblique Mercator by two points", "+proj=omerc +lat_0=40 +lat_1=35 +lon_1=-110 +lat_2=45 +lon_2=-100 +k=1 +datum=WGS84", [-115, 35, -95, 45]],
  ["Swiss LV95 (2056)", "+proj=somerc +lat_0=46.9524055555556 +lon_0=7.43958333333333 +k_0=1 +x_0=2600000 +y_0=1200000 +ellps=bessel +towgs84=674.374,15.056,405.346,0,0,0,0 +units=m +no_defs", [5.9, 45.8, 10.5, 47.8]],
  ["S-JTSK Krovak East North (5514)", "+proj=krovak +lat_0=49.5 +lon_0=24.8333333333333 +alpha=30.2881397527778 +k=0.9999 +x_0=0 +y_0=0 +ellps=bessel +towgs84=589,76,480,0,0,0,0 +units=m +no_defs", [12, 47.7, 22.6, 51.1]],
  ["Orthographic", "+proj=ortho +lat_0=35 +lon_0=135 +R=6371000", [105, 10, 165, 60]],
  ["Gnomonic", "+proj=gnom +lat_0=35 +lon_0=135 +R=6371000", [115, 20, 155, 50]],
  ["Equal Earth (8857)", "+proj=eqearth +lon_0=0 +x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs", [-180, -85, 180, 85]],
  ["Equal Earth on a sphere", "+proj=eqearth +lon_0=150 +R=6371000", [-30, -85, 330, 85]],
  ["Bonne", "+proj=bonne +lat_1=45 +lon_0=0 +datum=WGS84", [-60, 0, 60, 80]],
  ["Bonne on a sphere", "+proj=bonne +lat_1=60 +lon_0=10 +R=6371000", [-60, 0, 80, 80]],
  ["British National Grid (27700)", "+proj=tmerc +lat_0=49 +lon_0=-2 +k=0.9996012717 +x_0=400000 +y_0=-100000 +ellps=airy +towgs84=446.448,-125.157,542.06,0.15,0.247,0.842,-20.489 +units=m +no_defs", [-8, 49.9, 2, 60.9]],
  ["NTF Paris longitude and latitude", "+proj=longlat +a=6378249.2 +b=6356515 +towgs84=-168,-60,320,0,0,0,0 +pm=paris +no_defs", [-5, 42, 8, 51]],
];
for (const [name, def, area] of strings) crss.push({ name, def, area });

const EMPTY = new Float64Array(34);
let seed = 4242;
const rand = () => (seed = (Math.imul(seed, 1103515245) + 12345) >>> 0) / 4294967296;
const refOf = (crs) => (crs.def ? proj4.Proj(crs.def) : crs.name);
const slotsOf = (crs) => (crs.def ? parseProjString(crs.def) : EMPTY);
const codeOf = (crs) => (crs.def ? 0 : crs.code);
function ours(pairs, from, to) {
  const bytes = new Uint8Array(new Float64Array([...slotsOf(from), ...slotsOf(to), ...pairs.flat()]).buffer);
  const js = mbt.proj_bytes(bytes, codeOf(from), codeOf(to)).split(",").map(Number);
  const addr = gc.copyIn(bytes);
  const out = addr + bytes.length + 64;
  const n = gc.exports.proj_mem(addr, bytes.length, codeOf(from), codeOf(to), out);
  const wasm = Array.from(new Float64Array(gc.exports.memory.buffer.slice(out, out + n * 8)));
  return { js, wasm };
}
function reference(from, to, [x, y]) {
  try {
    const p = proj4(refOf(from), refOf(to), [x, y]);
    return p && Number.isFinite(p[0]) && Number.isFinite(p[1]) ? p : null;
  } catch {
    return null;
  }
}
const geographic = (crs) => (crs.def ? crs.def.includes("+proj=longlat") : [4326, 4612, 6668, 4301].includes(crs.code));

const worst = { meters: { js: 0, wasm: 0 }, degrees: { js: 0, wasm: 0 } };
const rows = [];
let compared = 0;
let skipped = 0;
function compare(label, pairs, from, to) {
  const refs = pairs.map((p) => reference(from, to, p));
  const kept = pairs.filter((_, i) => refs[i]);
  const ref = refs.filter(Boolean);
  skipped += pairs.length - kept.length;
  const { js, wasm } = ours(kept, from, to);
  const unit = geographic(to) ? "degrees" : "meters";
  const max = { js: 0, wasm: 0 };
  ref.forEach(([x, y], i) => {
    for (const [name, got] of [["js", js], ["wasm", wasm]]) {
      const d = Math.max(Math.abs(got[i * 2] - x), Math.abs(got[i * 2 + 1] - y));
      max[name] = Math.max(max[name], Number.isNaN(d) ? Infinity : d);
    }
    compared++;
  });
  worst[unit].js = Math.max(worst[unit].js, max.js);
  worst[unit].wasm = Math.max(worst[unit].wasm, max.wasm);
  rows.push({ label, from: from.name, to: to.name, unit, points: ref.length, maxJs: max.js, maxWasm: max.wasm });
}

const wgs = crss.find((c) => c.code === 4326);
for (const crs of crss) {
  const [w, s, e, n] = crs.area;
  const lonlat = Array.from({ length: POINTS }, () => [w + rand() * (e - w), s + rand() * (n - s)]);
  compare("forward", lonlat, wgs, crs);
  const xy = lonlat.map((p) => reference(wgs, crs, p)).filter(Boolean);
  compare("inverse", xy, crs, wgs);
}
// CRS to CRS, each datum shift on both sides: points in `area` taken into `from` first.
const byName = (name) => crss.find((c) => c.name === name);
for (const [from, to, area] of [
  ["EPSG:6677", "EPSG:6691", [139.2, 35.2, 140.2, 36.2]],
  ["EPSG:6677", "EPSG:3857", [139.2, 35.2, 140.2, 36.2]],
  ["EPSG:6677", "EPSG:30169", [139.2, 35.2, 140.2, 36.2]],
  ["EPSG:30169", "EPSG:3096", [139.2, 35.2, 140.2, 36.2]],
  ["Swiss LV95 (2056)", "Lambert 93 (2154)", [6, 46, 7, 47]],
  ["Amersfoort / RD New (28992)", "British National Grid (27700)", [3.5, 51, 5, 52]],
]) {
  const [w, s, e, n] = area;
  const pairs = Array.from({ length: POINTS }, () => reference(wgs, byName(from), [w + rand() * (e - w), s + rand() * (n - s)]));
  compare(`${from} to ${to}`, pairs, byName(from), byName(to));
}

console.log(`proj golden: ${crss.length} CRSs, ${compared} points (${skipped} beyond proj4js's reach left out); largest difference js ${worst.meters.js.toExponential(2)} m / ${worst.degrees.js.toExponential(2)}°, wasm-gc ${worst.meters.wasm.toExponential(2)} m / ${worst.degrees.wasm.toExponential(2)}°`);
await writeFile(path.join(ROOT, "bench/results/proj-golden.json"), JSON.stringify({ reference: "proj4js 2.22.0", points: POINTS, compared, skipped, worst, rows }, null, 2) + "\n");
const bad = rows.filter((r) => (r.unit === "meters" ? 1e-3 : 1e-8) < Math.max(r.maxJs, r.maxWasm));
for (const r of bad.slice(0, 20)) console.log("beyond tolerance:", JSON.stringify(r));
if (bad.length) process.exitCode = 1;
