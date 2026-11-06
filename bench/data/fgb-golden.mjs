// mbmap/data's FlatGeobuf vs flatgeobuf 4.6.1's `deserialize` on GSI features (国土地理院ベクトルタイル提供実験),
// every column and geometry type, bboxes from bytes and over HTTP, hostile files: identical or refused
// by both. Usage: node data/fgb-golden.mjs; writes bench/results/fgb-golden.json.
import { readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import path from "node:path";
import { geojson } from "flatgeobuf";
import proj4 from "proj4";
import { dataImports, dataReader } from "../../data_worker/js/read.mjs";
import { tableToGeoJSON, withIds } from "../../wasmio/js/table.mjs";
import { byteRange } from "../lib/serve.mjs";
import { GSI_TILES, gsiFeatures, same, wasmFile } from "./common.mjs";
import { bboxOf, columnsOf, fgbFile, G, T } from "./fgb-write.mjs";
import { ROOT } from "../lib/root.mjs";

// flatgeobuf logs every request and node range with console.debug.
console.debug = () => {};

const imports = dataImports(() => instance.exports.memory);
const { instance } = await WebAssembly.instantiate(
  await wasmFile("data_worker"),
  imports,
);
const projBytes = await wasmFile("proj_worker");
let projModule = null;
const reader = dataReader(instance.exports, imports, {
  proj: () => (projModule ??= WebAssembly.instantiate(projBytes, { Math }).then((r) => r.instance.exports)),
  prj: () => import("../../npm/src/prjwkt.ts"),
});

// --- Both sides as rows ---

function base64(b) {
  return Buffer.from(b.buffer, b.byteOffset, b.byteLength).toString("base64");
}

// A reference geometry as our tables hold it: collections flattened, x and y only, empty parts left out.
function flatten(g) {
  if (!g) return [];
  if (g.type === "GeometryCollection") return g.geometries.flatMap(flatten);
  const xy = (p) => [p[0], p[1]];
  const line = (l) => l.map(xy);
  const c = g.coordinates;
  const coordinates =
    g.type === "Point" ? (c.length === 0 ? null : xy(c)) :
    g.type === "MultiPoint" || g.type === "LineString" ? line(c) :
    g.type === "MultiLineString" ? c.map(line).filter((l) => l.length > 0) :
    g.type === "Polygon" ? c.map(line).filter((r) => r.length > 0) :
    c.map((p) => p.map(line).filter((r) => r.length > 0)).filter((p) => p.length > 0);
  if (coordinates === null || coordinates.length === 0) return [];
  return [{ type: g.type, coordinates }];
}

// flatgeobuf's features as our rows: a row per member, Binary values in base64.
function theirRows(features) {
  return features.flatMap((f) => {
    const properties = Object.fromEntries(Object.entries(f.properties).map(([k, v]) => [k, v instanceof Uint8Array ? base64(v) : v]));
    const gs = flatten(f.geometry);
    return (gs.length > 0 ? gs : [null]).map((geometry) => ({ id: f.id, geometry, properties }));
  });
}

async function theirs(input, options) {
  try {
    const out = [];
    for await (const f of geojson.deserialize(input, options)) out.push(f);
    return theirRows(out);
  } catch (e) {
    return { error: String(e.message ?? e) };
  }
}

// Our rows, Json columns (`json`: their names) parsed as flatgeobuf parses them.
async function ours(parts, options = {}, json = []) {
  try {
    const r = await reader.read("flatgeobuf", parts, options);
    const fc = r.ids ? withIds(tableToGeoJSON(r.table), r.ids) : tableToGeoJSON(r.table);
    return fc.features.map((f) => {
      const properties = { ...f.properties };
      for (const k of json) if (typeof properties[k] === "string") properties[k] = JSON.parse(properties[k]);
      return { id: f.id, geometry: f.geometry, properties };
    });
  } catch (e) {
    return { error: String(e.message ?? e) };
  }
}

const byId = (rows) => ("error" in rows ? rows : [...rows].sort((a, b) => a.id - b.id));

const results = {};
const failures = [];
function compare(group, label, got, want, eps = 0) {
  const r = (results[group] ??= { cases: 0, rows: 0, identical: 0, bothRefuse: 0, differ: 0 });
  r.cases++;
  const ok = "error" in want ? "error" in got : !("error" in got) && same(got, want, eps);
  if (!ok) {
    r.differ++;
    if (failures.length < 20) failures.push({ group, label, got: "error" in got ? got.error : got.slice(0, 2), want: "error" in want ? want.error : want.slice(0, 2) });
  } else if ("error" in want) r.bothRefuse++;
  else {
    r.identical++;
    r.rows += want.length;
  }
}
// Inputs where we deliberately differ: only our side is checked, and the case is listed in the results.
const deviations = [];
function deviation(group, label, got, expectError, why) {
  const ok = expectError ? "error" in got : !("error" in got);
  deviations.push({ group, label, why, ok });
  if (!ok) failures.push({ group, label, got: got.error ?? got.slice(0, 2), want: expectError ? "refused" : "read" });
}

// --- GSI tile features ---
const byLayer = await gsiFeatures();
// Features in the order of their box's center along x, as a Hilbert sort would group them.
const sorted = (fs) => [...fs].sort((a, b) => {
  const [p, q] = [bboxOf(a.geometry), bboxOf(b.geometry)];
  return p[0] + p[2] - (q[0] + q[2]);
});
const files = {};
for (const [name, fs] of Object.entries(byLayer)) {
  const features = sorted(fs).map((f) => ({ type: "Feature", geometry: f.geometry, properties: f.properties }));
  const columns = columnsOf(features);
  const json = columns.filter((c) => c.type === T.Json).map((c) => c.name);
  for (const nodeSize of [16, 2, 0]) {
    const bytes = fgbFile(features, { columns, nodeSize });
    files[`${name}-${nodeSize}`] = { bytes, json, features };
    compare("gsi", `${name}: ${features.length} features, node size ${nodeSize}`, await ours({ data: bytes }, {}, json), await theirs(bytes));
  }
  const kind = features[0].geometry.type;
  if (features.every((f) => f.geometry.type === kind)) {
    const bytes = fgbFile(features, { columns, geometryType: G[kind] });
    compare("gsi", `${name}: header type ${kind}`, await ours({ data: bytes }, {}, json), await theirs(bytes));
  }
}
// flatgeobuf's own writer (no index), on features whose properties it can write: the same keys everywhere.
for (const name of ["building", "contour"]) {
  const keys = Object.keys(byLayer[name][0].properties);
  const fs = byLayer[name].filter((f) => same(Object.keys(f.properties), keys));
  const bytes = geojson.serialize({ type: "FeatureCollection", features: fs });
  compare("gsi", `${name}: ${fs.length} features by flatgeobuf's serialize`, await ours({ data: bytes }), await theirs(bytes));
}

// --- Every column type ---
const typed = [
  ["byte", T.Byte, [-128, 127, 0]], ["ubyte", T.UByte, [255, 0, 7]], ["bool", T.Bool, [true, false, true]],
  ["short", T.Short, [-32768, 32767, 1]], ["ushort", T.UShort, [65535, 0, 2]], ["int", T.Int, [-(2 ** 31), 2 ** 31 - 1, 3]],
  ["uint", T.UInt, [2 ** 32 - 1, 0, 4]], ["long", T.Long, ["-9223372036854775808", "9007199254740993", "5"]],
  ["ulong", T.ULong, ["18446744073709551615", "9007199254740995", "6"]], ["float", T.Float, [0.1, -3.4e38, NaN]],
  ["double", T.Double, [Math.PI, -0, 1e-310]], ["string", T.String, ["﻿国土地理院", "", "a\u0000b"]],
  ["json", T.Json, [{ a: [1, { b: null }] }, "[1,2]", "\"text\""]], ["datetime", T.DateTime, ["2026-11-05T09:00:00Z", "2026-01-01", ""]],
  ["binary", T.Binary, [Uint8Array.from([0, 1, 2, 255]), new Uint8Array(0), Uint8Array.from([0xfb, 0xff])]],
];
const typedColumns = typed.map(([name, type]) => ({ name, type }));
const typedFeatures = [0, 1, 2].map((i) => ({
  type: "Feature",
  geometry: { type: "Point", coordinates: [139 + i, 35 + i] },
  properties: Object.fromEntries(typed.map(([name, , values]) => [name, values[i]])),
}));
const typedFile = fgbFile(typedFeatures, { columns: typedColumns });
compare("columns", "every column type", await ours({ data: typedFile }, {}, ["json"]), await theirs(typedFile));
// Sparse rows: a value missing from some features, columns out of order in the bytes.
const sparse = fgbFile(
  [{ properties: { b: 1 } }, { properties: { a: "x" } }, { properties: {} }].map((p, i) => ({ type: "Feature", geometry: { type: "Point", coordinates: [i, i] }, ...p })),
  { columns: [{ name: "a", type: T.String }, { name: "b", type: T.Int }] },
);
compare("columns", "values missing from some features", await ours({ data: sparse }), await theirs(sparse));

// --- Every geometry type, Z and M, collections, empty and missing geometries ---
const shapes = [
  { type: "Point", coordinates: [1, 2] },
  { type: "Point", coordinates: [1, 2, 3] },
  { type: "Point", coordinates: [1, 2, 3, 4] },
  { type: "MultiPoint", coordinates: [[1, 2], [3, 4]] },
  { type: "LineString", coordinates: [[1, 2, 10], [3, 4, 20]] },
  { type: "MultiLineString", coordinates: [[[1, 2], [3, 4]], [[5, 6], [7, 8], [9, 10]]] },
  { type: "Polygon", coordinates: [[[0, 0], [4, 0], [4, 4], [0, 0]], [[1, 1], [2, 1], [2, 2], [1, 1]]] },
  { type: "MultiPolygon", coordinates: [[[[0, 0], [1, 0], [1, 1], [0, 0]]], [[[5, 5], [6, 5], [6, 6], [5, 5]], [[5.2, 5.2], [5.4, 5.2], [5.4, 5.4], [5.2, 5.2]]]] },
  { type: "GeometryCollection", geometries: [{ type: "Point", coordinates: [1, 1] }, { type: "GeometryCollection", geometries: [{ type: "LineString", coordinates: [[0, 0], [1, 1]] }] }, { type: "MultiPolygon", coordinates: [[[[0, 0], [1, 0], [1, 1], [0, 0]]]] }] },
  { type: "LineString", coordinates: [] },
];
const shapeFile = fgbFile(shapes.map((geometry, i) => ({ type: "Feature", geometry, properties: { i } })), { columns: [{ name: "i", type: T.Int }] });
compare("geometries", `${shapes.length} geometries of every type, Z and M`, await ours({ data: shapeFile }), await theirs(shapeFile));
for (const g of shapes.slice(0, 9)) {
  const bytes = fgbFile([{ type: "Feature", geometry: g, properties: {} }, { type: "Feature", geometry: g, properties: {} }], { geometryType: G[g.type] });
  compare("geometries", `header type ${g.type}`, await ours({ data: bytes }), await theirs(bytes));
}
const noGeometry = fgbFile([{ type: "Feature", geometry: null, properties: { a: 1 } }], { columns: [{ name: "a", type: T.Int }] });
deviation("geometries", "a feature without geometry", await ours({ data: noGeometry }), false, "flatgeobuf throws reading the missing geometry; mbmap/data gives a row without one");
const curve = fgbFile([{ type: "Feature", geometry: { type: "LineString", coordinates: [[0, 0], [1, 1]] }, properties: {} }], { geometryType: 8 });
deviation("geometries", "a CircularString", await ours({ data: curve }), true, "flatgeobuf gives curves no coordinates; mbmap/data refuses them");

// --- CRS: an EPSG code, a WKT, and options.crs over the header's ---
const ix = "+proj=tmerc +lat_0=36 +lon_0=139.8333333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs";
const labels = byLayer.label.filter((f) => f.geometry.type === "Point").slice(0, 300);
const projected = labels.map((f) => ({ type: "Feature", geometry: { type: "Point", coordinates: proj4("EPSG:4326", ix, f.geometry.coordinates) }, properties: {} }));
const lonLat = labels.map((f, id) => ({ id, geometry: { type: "Point", coordinates: f.geometry.coordinates }, properties: {} }));
const wktIX = 'PROJCS["JGD2011 / Japan Plane Rectangular CS IX",GEOGCS["JGD2011",DATUM["Japanese_Geodetic_Datum_2011",SPHEROID["GRS 1980",6378137,298.257222101]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]],PROJECTION["Transverse_Mercator"],PARAMETER["latitude_of_origin",36],PARAMETER["central_meridian",139.833333333333],PARAMETER["scale_factor",0.9999],PARAMETER["false_easting",0],PARAMETER["false_northing",0],UNIT["metre",1]]';
compare("crs", "EPSG:6677 by code", await ours({ data: fgbFile(projected, { crs: { org: "EPSG", code: 6677 } }) }), lonLat, 1e-8);
compare("crs", "EPSG:6677 by code, no org", await ours({ data: fgbFile(projected, { crs: { code: 6677 } }) }), lonLat, 1e-8);
compare("crs", "a WKT without a code", await ours({ data: fgbFile(projected, { crs: { wkt: wktIX } }) }), lonLat, 1e-8);
compare("crs", "options.crs over EPSG:4326 in the header", await ours({ data: fgbFile(projected, { crs: { org: "EPSG", code: 4326 } }) }, { crs: 6677 }), lonLat, 1e-8);
const plain = fgbFile(lonLat.map((f) => ({ type: "Feature", ...f })), { crs: { org: "EPSG", code: 4326 } });
compare("crs", "EPSG:4326", await ours({ data: plain }), await theirs(plain));

// --- bbox through the index, from bytes ---
const rects = [];
for (let i = 0; i < 40; i++) {
  const x = 139.68 + ((i * 37) % 100) / 1000 * 1.5;
  const y = 35.63 + ((i * 53) % 100) / 1000 * 1.2;
  const s = 0.0005 * (1 + (i % 7) * 3);
  rects.push([x, y, x + s, y + s]);
}
rects.push([0, 0, 1, 1], [-180, -90, 180, 90]);
const asRect = ([minX, minY, maxX, maxY]) => ({ minX, minY, maxX, maxY });
for (const [name, f] of Object.entries(files)) {
  if (f.bytes && name.endsWith("-0")) {
    compare("bbox bytes", `${name}: no index`, await ours({ data: f.bytes }, { bbox: rects[0] }), await theirs(f.bytes, { rect: asRect(rects[0]) }));
    continue;
  }
  let n = 0;
  for (const r of rects) {
    const got = await ours({ data: f.bytes }, { bbox: r }, f.json);
    const want = await theirs(f.bytes, { rect: asRect(r) });
    compare("bbox bytes", `${name} ${r.join(",")}`, got, want);
    n += "error" in want ? 0 : want.length;
  }
}
const single = fgbFile([shapes[6] && { type: "Feature", geometry: shapes[6], properties: {} }]);
compare("bbox bytes", "one feature", await ours({ data: single }, { bbox: [1, 1, 2, 2] }), await theirs(single, { rect: asRect([1, 1, 2, 2]) }));

// --- bbox over HTTP range requests ---
const served = new Map();
let requests = 0;
let ranged = true;
const server = createServer((req, res) => {
  requests++;
  const body = served.get(new URL(req.url, "http://x").pathname);
  if (!body) return res.writeHead(404).end();
  const range = ranged ? byteRange(req.headers.range, body.length) : null;
  if (range === "bad") return res.writeHead(416).end();
  if (range) {
    res.writeHead(206, { "content-range": `bytes ${range[0]}-${range[1]}/${body.length}`, "content-length": range[1] - range[0] + 1 });
    return res.end(body.subarray(range[0], range[1] + 1));
  }
  res.writeHead(200, { "content-length": body.length }).end(body);
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const base = `http://127.0.0.1:${server.address().port}`;
const http = {};
files.shapes = { bytes: shapeFile, json: [] };
files.typed = { bytes: typedFile, json: ["json"] };
for (const name of ["building-16", "road-16", "contour-2", "label-16", "shapes", "typed"]) {
  served.set(`/${name}.fgb`, files[name].bytes);
  const url = `${base}/${name}.fgb`;
  const counts = { ours: 0, theirs: 0 };
  for (const r of rects.slice(0, 12).concat([[-180, -90, 180, 90], [0, 0, 1.5, 1.5], [139, 35, 140.5, 36.5]])) {
    requests = 0;
    const got = byId(await ours({ remote: { url } }, { bbox: r }, files[name].json));
    counts.ours += requests;
    requests = 0;
    const want = byId(await theirs(url, { rect: asRect(r) }));
    counts.theirs += requests;
    compare("bbox http", `${name} ${r.join(",")}`, got, want);
  }
  http[name] = { bytes: files[name].bytes.length, requests: counts };
}
ranged = false;
requests = 0;
compare("bbox http", "a server ignoring Range", byId(await ours({ remote: { url: `${base}/building-16.fgb` } }, { bbox: rects[3] })), byId(await theirs(files["building-16"].bytes, { rect: asRect(rects[3]) })));
http.ignoringRange = { requests };
ranged = true;
compare("bbox http", "404", await ours({ remote: { url: `${base}/none.fgb` } }, { bbox: rects[0] }), { error: "404" });

// --- Hostile files ---
const good = files["building-16"].bytes;
const view = (b) => new DataView(b.buffer, b.byteOffset, b.byteLength);
const headerEnd = 12 + view(good).getUint32(8, true);
const changed = (f) => {
  const b = good.slice();
  f(b, view(b));
  return b;
};
const hostile = [
  ["empty", new Uint8Array(0)],
  ["magic only", good.subarray(0, 8)],
  ["not FlatGeobuf", new TextEncoder().encode("{\"type\":\"FeatureCollection\",\"features\":[]}")],
  ["version 2", changed((b) => (b[3] = 2))],
  ["header size 0", changed((b, v) => v.setUint32(8, 0, true))],
];
for (const [label, b] of hostile) compare("hostile", label, await ours({ data: b }), await theirs(b));
// flatgeobuf's `deserialize` of bytes checks no header size and reads none of these as an error.
for (const [label, b] of [
  ["header size past the end", changed((b, v) => v.setUint32(8, good.length, true))],
  ["header size over 10 MB", changed((b, v) => v.setUint32(8, 11 * 1024 * 1024, true))],
  ["cut in the header", good.subarray(0, headerEnd - 10)],
]) deviation("hostile", label, await ours({ data: b }), true, "flatgeobuf reads no features from it without an error");
// Cut inside the index and inside the features: flatgeobuf reads past the end of its buffer there
// (DataView errors, or garbage), so only our refusal is checked.
for (const at of [headerEnd + 40, headerEnd + 4000, good.length - 3, good.length - 100]) {
  deviation("hostile", `cut at ${at} of ${good.length}`, await ours({ data: good.subarray(0, at) }), true, "flatgeobuf reads past its buffer or stops without an error");
}
const countAt = (() => {
  // The header's features_count field (u64) found as the one equal to the feature count.
  const n = BigInt(files["building-16"].features.length);
  for (let i = 12; i < headerEnd - 8; i++) if (view(good).getBigUint64(i, true) === n) return i;
  return -1;
})();
deviation("hostile", "a feature count of 2^40", await ours({ data: changed((b, v) => v.setBigUint64(countAt, 2n ** 40n, true)) }), true, "flatgeobuf allocates a tree of that size");
deviation("hostile", "bbox over a tree pointing back up", await ours({ data: changed((b, v) => {
  for (let i = 0; i < 16 * 16; i++) v.setBigUint64(headerEnd + i * 40 + 32, 0n, true);
}) }, { bbox: [-180, -90, 180, 90] }), true, "flatgeobuf walks it until its queue fails");
const noColumn = fgbFile([{ type: "Feature", geometry: shapes[0], properties: { b: 1 } }], { columns: [{ name: "a", type: T.Int }, { name: "b", type: T.Int }], headerColumns: 1 });
deviation("hostile", "a property of no column", await ours({ data: noColumn }), true, "flatgeobuf throws reading the column's name; mbmap/data refuses the file");

server.close();

let differ = 0;
let cases = 0;
for (const [group, r] of Object.entries(results)) {
  differ += r.differ;
  cases += r.cases;
  console.log(`${group}: ${r.cases} cases, ${r.rows} rows identical, ${r.bothRefuse} refused by both, ${r.differ} differ`);
}
const badDeviations = deviations.filter((d) => !d.ok).length;
console.log(`deviations: ${deviations.length} documented, ${badDeviations} not as documented`);
console.log(`requests per bbox: ${JSON.stringify(http)}`);
for (const f of failures) console.log("DIFF", JSON.stringify(f).slice(0, 600));
console.log(`${cases} cases, ${differ + badDeviations} differ`);
const pkg = async (name) => JSON.parse(await readFile(path.join(ROOT, "bench/node_modules", name, "package.json"), "utf8")).version;
await writeFile(
  path.join(ROOT, "bench/results/fgb-golden.json"),
  JSON.stringify({ env: { node: process.version, flatgeobuf: await pkg("flatgeobuf"), proj4: await pkg("proj4"), tiles: GSI_TILES }, results, http, deviations, differ: differ + badDeviations }, null, 2) + "\n",
);
if (differ + badDeviations > 0) process.exit(1);
