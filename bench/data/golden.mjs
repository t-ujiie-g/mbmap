// data.wasm vs papaparse 5.7.0, betterknown 1.2.0, wkx 0.5.0 and (golden-more.mjs) shpjs, topojson-client
// and proj4 on hand-written cases and GSI features (国土地理院ベクトルタイル提供実験): rows identical or refused
// by both. Usage: node data/golden.mjs; writes bench/results/data-golden.json.

// shpjs's dates are local midnights: the time zone is pinned so they read the same anywhere.
process.env.TZ = "UTC";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { VectorTile } from "@mapbox/vector-tile";
import { geoJSONToWkt, wktToGeoJSON } from "betterknown";
import Papa from "papaparse";
import { PbfReader } from "pbf";
import wkx from "wkx";
import { dataImports, dataReader } from "../../data_worker/js/read.mjs";
import { tableToGeoJSON } from "../../wasmio/js/table.mjs";
import { ROOT } from "../lib/root.mjs";
import { moreCases } from "./golden-more.mjs";

// papaparse warns on the console when it renames repeated headers.
const warn = console.warn;
console.warn = (...args) => /Duplicate headers/.test(args[0]) || warn(...args);

const imports = dataImports(() => instance.exports.memory);
const { instance } = await WebAssembly.instantiate(
  await readFile(path.join(ROOT, "_build/wasm-gc/release/build/data_worker/data_worker.wasm")),
  imports,
);
const w = instance.exports;
const projBytes = await readFile(path.join(ROOT, "_build/wasm-gc/release/build/proj_worker/proj_worker.wasm"));
let projModule = null;
const loads = { proj: 0, prj: 0 };
const reader = dataReader(w, imports, {
  proj: () => (loads.proj++, (projModule ??= WebAssembly.instantiate(projBytes, { Math }).then((r) => r.instance.exports))),
  prj: () => (loads.prj++, import("../../npm/src/prjwkt.ts")),
});
const encoder = new TextEncoder();
const bytesOf = (data) => (typeof data === "string" ? encoder.encode(data) : new Uint8Array(data));

function input(parts) {
  const len = parts.reduce((s, b) => s + b.length, 0);
  let at = w.prepare_input(len);
  for (const b of parts) {
    new Uint8Array(w.memory.buffer, at, b.length).set(b);
    at += b.length;
  }
}

// Our rows ({geometry, properties}), or {error}.
function ours(format, data, options = {}) {
  let n;
  if (format === "csv") {
    const { delimiter, header = true, dynamicTyping = true, latitude, longitude, geometry } = options;
    const names = encoder.encode(`${latitude ?? ""}\0${longitude ?? ""}\0${geometry ?? ""}\0`);
    input([names, bytesOf(data)]);
    n = w.read_csv(names.length, delimiter === undefined ? -1 : delimiter.charCodeAt(0), header ? 1 : 0, dynamicTyping ? 1 : 0);
  } else {
    input([bytesOf(data)]);
    n = format === "wkt" ? w.read_wkt() : w.read_wkb();
  }
  const out = new Uint8Array(w.memory.buffer.slice(w.output_addr(), w.output_addr() + Math.abs(n)));
  if (n < 0) return { error: new TextDecoder().decode(out) };
  return tableToGeoJSON(out).features.map((f) => ({ geometry: f.geometry, properties: f.properties }));
}

// A reference geometry as our tables hold it: collections flattened, x and y only, empty
// rings, parts and members left out, a WKB point of NaNs empty. Null for a refusal: a
// coordinate that is not finite.
function flatten(g) {
  if (g === null || g === undefined) return [];
  if (g.type === "GeometryCollection") {
    const out = [];
    for (const m of g.geometries) {
      const f = flatten(m);
      if (f === null) return null;
      out.push(...f);
    }
    return out;
  }
  const empty = (p) => p.length === 0 || (Number.isNaN(p[0]) && Number.isNaN(p[1]));
  const xy = (p) => [p[0], p[1]];
  const line = (l) => l.filter((p) => !empty(p)).map(xy);
  const polygon = (rings) => rings.map(line).filter((r) => r.length > 0);
  const c = g.coordinates;
  const coordinates =
    g.type === "Point" ? (empty(c) ? null : xy(c)) :
    g.type === "MultiPoint" || g.type === "LineString" ? line(c) :
    g.type === "MultiLineString" ? c.map(line).filter((l) => l.length > 0) :
    g.type === "Polygon" ? polygon(c) :
    c.map(polygon).filter((p) => p.length > 0);
  if (coordinates === null || coordinates.length === 0) return [];
  if (!coordinates.flat(3).every(Number.isFinite)) return null;
  return [{ type: g.type, coordinates }];
}

// Rows of one record: a row per member of its geometry, or one without geometry; null if refused.
function rowsOf(geometry, properties = {}) {
  const gs = flatten(geometry);
  if (gs === null) return null;
  return gs.length > 0 ? gs.map((g) => ({ geometry: g, properties })) : [{ geometry: null, properties }];
}

// papaparse's FLOAT test of `dynamicTyping` (papaparse.js), for coordinates of untyped fields.
const FLOAT = /^\s*-?(\d+\.?|\.\d+|\d+\.\d+)([eE][-+]?\d+)?\s*$/;
const typedNumber = (s) => (typeof s === "number" ? s : typeof s === "string" && FLOAT.test(s) && Math.abs(parseFloat(s)) < 2 ** 53 ? parseFloat(s) : null);

const LATITUDE = ["lat", "latitude", "y", "緯度"];
const LONGITUDE = ["lon", "lng", "long", "longitude", "x", "経度"];
const GEOMETRY = ["wkt", "geometry", "the_geom", "geom"];
const find = (fields, names) => {
  for (const n of names) {
    const i = fields.findIndex((f) => f.toLowerCase() === n);
    if (i >= 0) return fields[i];
  }
  return null;
};

// A WKT or hexadecimal WKB cell's geometry by betterknown or wkx; undefined if neither reads it.
function cellGeometry(v) {
  if (typeof v !== "string" || v.trim() === "") return undefined;
  try {
    return /^\s*[0-9a-f]/i.test(v) ? wkx.Geometry.parse(Buffer.from(v.trim(), "hex")).toGeoJSON() : wktToGeoJSON(v.replace(/[\t\n\r]/g, " "));
  } catch {
    return undefined;
  }
}

// papaparse's rows mapped as mbmap/data maps CSV rows, or null if it reports a quoting error.
function papaRows(text, options = {}) {
  const { delimiter, header = true, dynamicTyping = true, latitude, longitude, geometry } = options;
  const r = Papa.parse(text, { header, dynamicTyping, skipEmptyLines: true, delimiter });
  if (r.errors.some((e) => e.type === "Quotes")) return null;
  const rows = header ? r.data : r.data.map((a) => Object.fromEntries(a.map((v, i) => [String(i), v])));
  const fields = header ? r.meta.fields : [];
  let g = geometry ?? null;
  let [lat, lon] = [latitude ?? null, longitude ?? null];
  if (!g && !lat) {
    const named = find(fields, GEOMETRY);
    const first = named && rows.find((row) => row[named] !== undefined && row[named] !== null && row[named] !== "");
    if (first && cellGeometry(first[named]) !== undefined) g = named;
    else [lat, lon] = [find(fields, LATITUDE), find(fields, LONGITUDE)];
  }
  return rows.flatMap((row) => {
    const properties = Object.fromEntries(Object.entries(row).filter(([k]) => k !== "__parsed_extra" && k !== g));
    if (g) return rowsOf(cellGeometry(row[g]) ?? null, properties) ?? [{ geometry: null, properties }];
    const [y, x] = [typedNumber(row[lat]), typedNumber(row[lon])];
    return rowsOf(lat && x !== null && y !== null ? { type: "Point", coordinates: [x, y] } : null, properties);
  });
}

// betterknown's rows of WKT geometries, each its own input; null if it refuses one.
function wktRows(texts) {
  const out = [];
  for (const t of texts) {
    let g;
    try {
      g = wktToGeoJSON(t.replace(/[\t\n\r]/g, " "));
    } catch {
      return null;
    }
    const rows = rowsOf(g);
    if (rows === null) return null;
    out.push(...rows);
  }
  return out;
}

// wkx's rows of WKB geometries, each its own buffer; null if it refuses one.
function wkbRows(buffers) {
  const out = [];
  for (const b of buffers) {
    let g;
    try {
      g = wkx.Geometry.parse(Buffer.from(b)).toGeoJSON();
    } catch {
      return null;
    }
    const rows = rowsOf(g);
    if (rows === null) return null;
    out.push(...rows);
  }
  return out;
}

// Equal as JSON with numbers by Object.is, or within `eps` if given; a Date of papaparse equals
// the ISO string it came from.
function same(a, b, eps = 0) {
  if (b instanceof Date) return typeof a === "string" && new Date(a).getTime() === b.getTime();
  if (typeof a === "number" && typeof b === "number" && eps > 0) return Math.abs(a - b) <= eps;
  if (typeof a === "number" || typeof b === "number") return Object.is(a, b);
  if (a === null || b === null || typeof a !== "object" || typeof b !== "object") return a === b;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  const ka = Object.keys(a);
  const kb = Object.keys(b);
  return ka.length === kb.length && ka.every((k) => Object.hasOwn(b, k) && same(a[k], b[k], eps));
}

const results = {};
const failures = [];
function compare(group, label, got, want, eps = 0) {
  const r = (results[group] ??= { cases: 0, rows: 0, identical: 0, bothRefuse: 0, differ: 0 });
  r.cases++;
  const ok = want === null ? "error" in got : !("error" in got) && same(got, want, eps);
  if (!ok) {
    r.differ++;
    if (failures.length < 20) failures.push({ group, label, got: "error" in got ? got.error : got.slice(0, 3), want: want?.slice(0, 3) ?? "refused" });
  } else if (want === null) r.bothRefuse++;
  else {
    r.identical++;
    r.rows += want.length;
  }
}
// Inputs where we deliberately differ (refusing what the reference takes leniently, or reading
// what it refuses): only our side is checked, and the case is listed in the results.
const deviations = [];
function deviation(group, label, got, expectError, why) {
  const ok = expectError ? "error" in got : !("error" in got);
  deviations.push({ group, label, why, ok });
  if (!ok) failures.push({ group, label, got: got.error ?? got, want: expectError ? "refused" : "read" });
}

// WKB written by hand: `dims` "", "Z", "M" or "ZM" (filled with 7s), `ewkb` with flags and
// `srid`, `little` per geometry (`flip` alternates members' byte orders).
function toWkb(g, { little = true, dims = "", ewkb = false, srid, flip = false } = {}) {
  const out = [];
  const u32 = (v, le) => {
    const b = Buffer.alloc(4);
    le ? b.writeUInt32LE(v >>> 0) : b.writeUInt32BE(v >>> 0);
    out.push(...b);
  };
  const f64 = (v, le) => {
    const b = Buffer.alloc(8);
    le ? b.writeDoubleLE(v) : b.writeDoubleBE(v);
    out.push(...b);
  };
  const CODES = { Point: 1, LineString: 2, Polygon: 3, MultiPoint: 4, MultiLineString: 5, MultiPolygon: 6, GeometryCollection: 7 };
  const extra = dims.length;
  const header = (type, le, top) => {
    out.push(le ? 1 : 0);
    let code = CODES[type];
    if (ewkb) {
      if (dims.includes("Z")) code |= 0x80000000;
      if (dims.includes("M")) code |= 0x40000000;
      if (top && srid !== undefined) code |= 0x20000000;
    } else code += { "": 0, Z: 1000, M: 2000, ZM: 3000 }[dims];
    u32(code, le);
    if (ewkb && top && srid !== undefined) u32(srid, le);
  };
  const pos = (p, le) => {
    f64(p[0], le);
    f64(p[1], le);
    for (let i = 0; i < extra; i++) f64(7, le);
  };
  const write = (g, le, top) => {
    header(g.type, le, top);
    const c = g.coordinates;
    const member = (type, coordinates, i) => write({ type, coordinates }, flip ? (i % 2 === 0) !== le : le, false);
    switch (g.type) {
      case "Point": return c.length === 0 ? (pos([NaN, NaN], le)) : pos(c, le);
      case "LineString": u32(c.length, le); return c.forEach((p) => pos(p, le));
      case "Polygon": u32(c.length, le); return c.forEach((r) => { u32(r.length, le); r.forEach((p) => pos(p, le)); });
      case "MultiPoint": u32(c.length, le); return c.forEach((p, i) => member("Point", p, i));
      case "MultiLineString": u32(c.length, le); return c.forEach((l, i) => member("LineString", l, i));
      case "MultiPolygon": u32(c.length, le); return c.forEach((p, i) => member("Polygon", p, i));
      default: u32(g.geometries.length, le); return g.geometries.forEach((m, i) => write(m, flip ? (i % 2 === 0) !== le : le, false));
    }
  };
  write(g, little, true);
  return Uint8Array.from(out);
}
const hex = (bytes) => Buffer.from(bytes).toString("hex");
const join = (arrays) => Uint8Array.from(arrays.flatMap((a) => [...a]));

// --- Hand-written CSV ---
const CSV = [
  ["typing", "a,b,c,d,e,f,g,h,i,j,k,l,m,n\n007,1e3,NaN,,-0,1.,.5,TRUE,True,\" 12 \",9007199254740993,1e400,+1,0x10\n\"1\", 2　,false,FALSE,1e-400,\"x\"\"\",-.5E+1,2020-01-01T00:00:00Z,true,\t3\n"],
  ["typing off", "a,b,lat,lon\n1,,35.5,139.25\n007,x, 35 ,1e2\n", { dynamicTyping: false }],
  ["quotes and line breaks", "name,note\n\"a \"\"b\"\"\",\"line 1\nline 2\"\n\"c\"  ,d\nx,\"\"\n\"e\",\"f\""],
  ["CRLF", "a,b\r\n1,2\r\n\"x\r\ny\",3\r\n"],
  ["CR", "a,b\r1,2\r3,4"],
  ["BOM", "﻿a,b\n1,2\n"],
  ["empty lines", "\n\na,b\n1,2\n\n3,4\n \n"],
  ["extra and missing fields", "a,b\n1,2,3,4\n5\n6,\n"],
  ["repeated headers", "a,a,a_1,a\n1,2,3,4\n"],
  ["empty header", "a,,b\n1,2,3\n"],
  ["tab guessed", "name\tlat\tlon\nA\t35.1\t139.2\nB\t35.3\t139.4\n"],
  ["semicolon guessed", "name;lat;lon\nA;35,1;139,2\n"],
  ["pipe guessed", "a|b\n1|2\n"],
  ["guess by consistency", "a;b,c\n1;2\n3;4,5,6\n"],
  ["one column", "a\n1\n2\n"],
  ["header only", "a,b\n"],
  ["empty", ""],
  ["delimiter given", "a,b;c\n1,2;3\n", { delimiter: ";" }],
  ["no header", "1,2\n3,4,5\n", { header: false }],
  ["lat lon by name", "name,Lat,LONGITUDE\na,35.5,139.25\nb,,139\nc,91x,1\nd,\"36\",\"140\"\n"],
  ["Japanese headers", "名前,緯度,経度,備考\n東京駅,35.6812,139.7671,\"丸の内, 千代田区\"\n大阪駅,34.7025,135.4959,\n"],
  ["x y lng", "x,y,lng\n1,2,3\n"],
  ["lat lon given", "a,b,lat,lon\n1,2,3,4\n", { latitude: "a", longitude: "b" }],
  ["WKT column", "id,WKT\n1,\n2,POINT (1 2)\n3,\"GEOMETRYCOLLECTION (POINT (3 4), LINESTRING (0 0, 1 1))\"\n4,nope\n5,\"POLYGON ((0 0, 1 0, 1 1, 0 0))\"\n6,SRID=4326;POINT(5 6)\n"],
  ["hex WKB column", `geom,name\n${hex(toWkb({ type: "Point", coordinates: [139.7, 35.6] }))},a\n${hex(toWkb({ type: "LineString", coordinates: [[0, 0], [1, 2]] }, { ewkb: true, srid: 4326, little: false }))},b\n`],
  ["geometry column not a geometry", "geometry,lat,lon\nround,1,2\nPOINT (5 6),3,4\n"],
  ["geometry given", "a,b,shape\n1,2,POINT (7 8)\n", { geometry: "shape" }],
  ["dates", "when,n\n2020-01-01T00:00:00Z,1\n2020-01-01T09:00:00.123+09:00,2\n2020-13-01,3\n"],
  ["unterminated quote", "a,b\n\"x,1\n"],
  ["text after a quote", "a,b\n\"x\"y,1\n"],
  ["spaces after a final quote", "a\n\"x\"  "],
];
for (const [label, text, options] of CSV) compare("csv cases", label, ours("csv", text, options), papaRows(text, options));

// --- Hand-written WKT ---
const WKT = [
  "POINT (1 2)", "POINT(-1.5e2 .25)", "point (1 2)", "POINT Z (1 2 3)", "POINTZ(1 2 3)", "POINT M (1 2 3)", "POINT ZM (1 2 3 4)",
  "POINT EMPTY", "POINT Z EMPTY", "LINESTRING (0 0, 1 1, 2 0)", "LINESTRING EMPTY", "LINESTRING Z (0 0 1, 1 1 2)",
  "POLYGON ((0 0, 4 0, 4 4, 0 0), (1 1, 2 1, 2 2, 1 1))", "POLYGON EMPTY", "MULTIPOINT (1 2, 3 4)", "MULTIPOINT ((1 2), (3 4))",
  "MULTIPOINT EMPTY", "MULTILINESTRING ((0 0, 1 1), (2 2, 3 3))", "MULTIPOLYGON (((0 0, 1 0, 1 1, 0 0)), ((5 5, 6 5, 6 6, 5 5), (5.2 5.2, 5.4 5.2, 5.2 5.4, 5.2 5.2)))",
  "MULTIPOLYGON ZM (((0 0 1 2, 1 0 1 2, 1 1 1 2, 0 0 1 2)))", "GEOMETRYCOLLECTION (POINT (1 2), LINESTRING (0 0, 1 1))",
  "GEOMETRYCOLLECTION (POINT (1 2), GEOMETRYCOLLECTION (POLYGON ((0 0, 1 0, 1 1, 0 0)), POINT EMPTY))", "GEOMETRYCOLLECTION EMPTY",
  "SRID=4326;POINT (139.7671 35.6812)", "srid=4326;MULTIPOINT (1 2)", "SRID=0;POINT (1 2)", "POINT (0.1234567890123456789 -179.99999999999997)",
  "LINESTRING (1e-7 2E+3, 3.0 4.)", "POINT\t(1\n2)",
];
for (const t of WKT) compare("wkt cases", t, ours("wkt", t), wktRows([t]));
const WKT_REFUSED = ["POINT (1)", "POINT (1 2", "POINT ()", "POINT 1 2", "CIRCLE (1 2)", "POLYGON (1 2)", "MULTIPOINT (EMPTY)", "POINT Z (1 2)", "SRID=x;POINT (1 2)", "POINT (NaN 1)", "POINT (1e400 1)", "LINESTRING (0 0, 1)", ""];
for (const t of WKT_REFUSED.slice(0, -1)) compare("wkt refused", t, ours("wkt", t), null);
compare("wkt cases", "empty input", ours("wkt", ""), []);
deviation("wkt", "POINT (1 2) trailing", ours("wkt", "POINT (1 2) trailing"), true, "betterknown stops after one geometry; mbmap/data reads geometries to the end and refuses other text");
deviation("wkt", "POINT (1a 2)", ours("wkt", "POINT (1a 2)"), true, "betterknown's parseFloat takes a number's prefix; mbmap/data refuses the field");
deviation("wkt", "POINT (1 2 3)", ours("wkt", "POINT (1 2 3)"), false, "betterknown refuses Z without a tag; mbmap/data takes 2 to 4 ordinates when untagged, as GDAL's older WKT writes them");
deviation("wkt", "<http://www.opengis.net/def/crs/epsg/0/4326>POINT (1 2)", ours("wkt", "<http://www.opengis.net/def/crs/epsg/0/4326>POINT (1 2)"), true, "betterknown takes an OGC CRS URI prefix; mbmap/data does not");

// --- Hand-written WKB ---
const SHAPES = [
  { type: "Point", coordinates: [139.5, 35.25] },
  { type: "Point", coordinates: [] },
  { type: "LineString", coordinates: [[0, 0], [1, 1], [2, -0.5]] },
  { type: "LineString", coordinates: [] },
  { type: "Polygon", coordinates: [[[0, 0], [4, 0], [4, 4], [0, 0]], [[1, 1], [2, 1], [2, 2], [1, 1]]] },
  { type: "Polygon", coordinates: [] },
  { type: "MultiPoint", coordinates: [[1, 2], [3, 4], [5, 6]] },
  { type: "MultiLineString", coordinates: [[[0, 0], [1, 1]], [[2, 2], [3, 3]]] },
  { type: "MultiPolygon", coordinates: [[[[0, 0], [1, 0], [1, 1], [0, 0]]], [[[5, 5], [6, 5], [6, 6], [5, 5]]]] },
  { type: "GeometryCollection", geometries: [{ type: "Point", coordinates: [1, 2] }, { type: "GeometryCollection", geometries: [{ type: "LineString", coordinates: [[0, 0], [1, 1]] }] }, { type: "Point", coordinates: [] }] },
  { type: "GeometryCollection", geometries: [] },
];
for (const g of SHAPES) {
  for (const little of [true, false]) {
    for (const dims of ["", "Z", "M", "ZM"]) {
      for (const [kind, opts] of [["ISO", {}], ["EWKB", { ewkb: true }], ["EWKB SRID", { ewkb: true, srid: 4326 }], ["flipped", { flip: true }]]) {
        const b = toWkb(g, { little, dims, ...opts });
        const label = `${g.type} ${little ? "LE" : "BE"} ${dims || "XY"} ${kind}`;
        compare("wkb cases", label, ours("wkb", b), wkbRows([b]));
        compare("wkb hex cases", label, ours("wkb", hex(b).toUpperCase()), wkbRows([b]));
      }
    }
  }
}
// A MultiPoint with an empty (NaN) member, and a line with a NaN coordinate (refused by both).
const nanMember = toWkb({ type: "MultiPoint", coordinates: [[1, 2], [NaN, NaN], [3, 4]] });
compare("wkb cases", "MultiPoint with an empty member", ours("wkb", nanMember), wkbRows([nanMember]));
const point = toWkb({ type: "Point", coordinates: [1, 2] });
for (const [label, b] of [
  ["NaN in a line", toWkb({ type: "LineString", coordinates: [[0, 0], [NaN, 1]] })],
  ["truncated", point.subarray(0, 15)],
  ["type 8", Uint8Array.from([1, 8, 0, 0, 0, ...point.subarray(5)])],
  ["type 4001", Uint8Array.from([1, 0xa1, 0x0f, 0, 0, ...point.subarray(5)])],
  ["count past the end", Uint8Array.from([1, 2, 0, 0, 0, 0xff, 0xff, 0xff, 0x0f])],
  ["empty input", new Uint8Array(0)],
]) compare("wkb refused", label, ours("wkb", b), b.length === 0 ? [] : wkbRows([b]));
deviation("wkb", "byte order 2", ours("wkb", Uint8Array.from([2, ...point.subarray(1)])), true, "wkx reads any byte but 0 as little-endian");
deviation("wkb", "MultiPoint of a LineString", ours("wkb", Uint8Array.from([1, 4, 0, 0, 0, 1, 0, 0, 0, ...toWkb(SHAPES[2])])), true, "wkx takes members of any type");
deviation("wkb", "trailing bytes", ours("wkb", join([point, [1, 2, 3]])), true, "wkx ignores bytes after the geometry; mbmap/data reads geometries to the end");

// --- GSI tile features in every format ---
const manifest = JSON.parse(await readFile(path.join(ROOT, "bench/fixtures/gsi-bvmap.manifest.json"), "utf8"));
const TILES = ["14/14552/6451", "14/14551/6450", "14/14553/6452"].filter((k) => k in manifest.tiles);
if (TILES.length === 0) throw new Error("no GSI fixtures: run npm run fixtures");
const byLayer = {};
for (const key of TILES) {
  const [z, x, y] = key.split("/").map(Number);
  const tile = new VectorTile(new PbfReader(await readFile(path.join(ROOT, "bench/fixtures/gsi-bvmap", `${key}.pbf`))));
  for (const name of ["label", "road", "building", "contour", "railway", "waterarea"]) {
    const layer = tile.layers[name];
    for (let i = 0; layer && i < layer.length; i++) (byLayer[name] ??= []).push(layer.feature(i).toGeoJSON(x, y, z));
  }
}
const features = Object.values(byLayer).flat();
// Pairs of buildings as MultiPolygons and a point with a road as a collection, for the multi kinds.
const buildings = (byLayer.building ?? []).filter((f) => f.geometry.type === "Polygon");
for (let i = 0; i + 1 < buildings.length && i < 200; i += 2) {
  features.push({ properties: {}, geometry: { type: "MultiPolygon", coordinates: [buildings[i].geometry.coordinates, buildings[i + 1].geometry.coordinates] } });
}
features.push({ properties: {}, geometry: { type: "GeometryCollection", geometries: [byLayer.label[0].geometry, byLayer.road[0].geometry] } });
const geometries = features.map((f) => f.geometry).filter((g) => g.type !== "Polygon" || g.coordinates.length > 0);

const wkts = geometries.map((g) => geoJSONToWkt(g));
compare("gsi wkt", `${wkts.length} geometries`, ours("wkt", wkts.join("\n")), wktRows(wkts));
const ewkts = wkts.map((t) => `SRID=4326;${t}`);
compare("gsi wkt", `${ewkts.length} EWKT geometries`, ours("wkt", ewkts.join("\n")), wktRows(ewkts));
const wkbs = geometries.map((g) => Uint8Array.from(wkx.Geometry.parseGeoJSON(g).toWkb()));
compare("gsi wkb", `${wkbs.length} geometries (wkx's writer)`, ours("wkb", join(wkbs)), wkbRows(wkbs));
const ewkbs = geometries.map((g) => {
  const x = wkx.Geometry.parseGeoJSON(g);
  x.srid = 4326;
  return Uint8Array.from(x.toEwkb());
});
compare("gsi wkb", `${ewkbs.length} EWKB geometries (wkx's writer)`, ours("wkb", join(ewkbs)), wkbRows(ewkbs));
compare("gsi wkb", `${ewkbs.length} EWKB geometries as hex lines`, ours("wkb", ewkbs.map(hex).join("\n")), wkbRows(ewkbs));
const bes = geometries.map((g) => toWkb(g, { little: false, dims: "Z", flip: true }));
compare("gsi wkb", `${bes.length} big-endian ISO Z geometries`, ours("wkb", join(bes)), wkbRows(bes));

const points = byLayer.label ?? [];
const columns = [...new Set(points.flatMap((f) => Object.keys(f.properties)))];
const rows = points.map((f) => ({ ...f.properties, lat: f.geometry.coordinates[1], lon: f.geometry.coordinates[0] }));
const csv = Papa.unparse(rows, { columns: [...columns, "lat", "lon"] });
compare("gsi csv", `${rows.length} label points, lat and lon`, ours("csv", csv), papaRows(csv));
const tsv = Papa.unparse(rows.map((r) => ({ 名前: r.knj, 緯度: r.lat, 経度: r.lon, かな: r.kana })), { delimiter: "\t", newline: "\r\n" });
compare("gsi csv", `${rows.length} label points as TSV with 緯度 and 経度`, ours("csv", tsv), papaRows(tsv));
compare("gsi csv", `${rows.length} label points untyped`, ours("csv", csv, { dynamicTyping: false }), papaRows(csv, { dynamicTyping: false }));
const shapes = features.filter((f) => f.geometry.type !== "Point").map((f) => ({ ftCode: f.properties.ftCode ?? "", WKT: geoJSONToWkt(f.geometry) }));
const shapesCsv = Papa.unparse(shapes);
compare("gsi csv", `${shapes.length} lines and polygons as a WKT column`, ours("csv", shapesCsv), papaRows(shapesCsv));
const hexCsv = Papa.unparse(geometries.map((g, i) => ({ i, the_geom: hex(ewkbs[geometries.indexOf(g)]) })));
compare("gsi csv", `${geometries.length} geometries as a hex EWKB column`, ours("csv", hexCsv), papaRows(hexCsv));

await moreCases({ reader, loads, byLayer, geometries, rowsOf, compare, deviation });

let differ = 0;
let cases = 0;
for (const [group, r] of Object.entries(results)) {
  differ += r.differ;
  cases += r.cases;
  console.log(`${group}: ${r.cases} cases, ${r.rows} rows identical, ${r.bothRefuse} refused by both, ${r.differ} differ`);
}
const badDeviations = deviations.filter((d) => !d.ok).length;
console.log(`deviations: ${deviations.length} documented, ${badDeviations} not as documented`);
for (const f of failures) console.log("DIFF", JSON.stringify(f).slice(0, 400));
console.log(`${cases} cases, ${differ + badDeviations} differ`);
const pkg = async (name) => JSON.parse(await readFile(path.join(ROOT, "bench/node_modules", name, "package.json"), "utf8")).version;
await writeFile(
  path.join(ROOT, "bench/results/data-golden.json"),
  JSON.stringify({
    env: {
      node: process.version,
      ...Object.fromEntries(await Promise.all(["papaparse", "betterknown", "wkx", "shpjs", "topojson-client", "topojson-server", "proj4"].map(async (p) => [p, await pkg(p)]))),
      tiles: TILES,
    },
    results,
    deviations,
    differ: differ + badDeviations,
  }, null, 2) + "\n",
);
if (differ + badDeviations > 0) process.exit(1);
