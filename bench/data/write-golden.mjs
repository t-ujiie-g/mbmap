// mbmap/data's CSV and KML vs papaparse 5.7.0's `unparse` (WKT by betterknown 1.2.0) and tokml 0.4.0's
// `toKML` of the table's `toGeoJSON`, on GSI features (国土地理院ベクトルタイル提供実験) and hand-written
// cases, byte for byte. Usage: node data/write-golden.mjs; writes bench/results/write-golden.json.
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { toKML } from "@placemarkio/tokml";
import { geoJSONToWkt } from "betterknown";
import Papa from "papaparse";
import { dataImports, dataReader } from "../../data_worker/js/read.mjs";
import { hostText } from "../../wasmio/js/host.mjs";
import { tableInfo, tableToGeoJSON, withIds } from "../../wasmio/js/table.mjs";
import { ROOT } from "../lib/root.mjs";
import { GSI_TILES, gsiFeatures, wasmFile } from "./common.mjs";
import { fgbFile, T } from "./fgb-write.mjs";

const imports = dataImports(() => instance.exports.memory);
const { instance } = await WebAssembly.instantiate(await wasmFile("data_worker"), imports);
const xmlBytes = await wasmFile("xml_worker");
let xmlModule = null;
const reader = dataReader(instance.exports, imports, {
  xml: () => (xmlModule ??= WebAssembly.instantiate(xmlBytes, { Math, host: hostText() }).then((r) => r.instance.exports)),
});
const encoder = new TextEncoder();
const decoder = new TextDecoder();

/** A table read from a GeoJSON object (or FlatGeobuf bytes): `{ table, ids, fc }`, `fc` what `toGeoJSON` gives. */
async function tableOf(input) {
  const r = input instanceof Uint8Array
    ? await reader.read("flatgeobuf", { data: input }, {})
    : await reader.read("geojson", { data: encoder.encode(JSON.stringify(input)) }, {});
  const fc = tableToGeoJSON(r.table);
  return { table: r.table, ids: r.ids, fc: r.ids ? withIds(fc, r.ids) : fc };
}

async function ours(format, t, options = {}) {
  try {
    return decoder.decode(await reader.write(format, t.table.slice(0), t.ids?.slice(0) ?? null, options));
  } catch (e) {
    return { error: String(e.message ?? e) };
  }
}

/** papaparse's CSV of `t` laid out as `write` lays it (the columns, then the geometry's not among them). */
function theirCsv(t, { delimiter = 44, header = true, geometryFormat, geometry = "wkt", longitude = "longitude", latitude = "latitude" } = {}) {
  const kinds = t.fc.features.map((f) => f.geometry?.type ?? null);
  const mode = geometryFormat ?? (kinds.every((k) => k === null) ? "none" : kinds.every((k) => k === null || k === "Point") ? "lonlat" : "wkt");
  if (mode === "lonlat" && !kinds.every((k) => k === null || k === "Point")) return { error: "not a point" };
  const extra = mode === "wkt" ? [geometry] : mode === "lonlat" ? [longitude, latitude] : [];
  const { columns } = tableInfo(t.table);
  const fields = [...columns, ...extra.filter((n) => !columns.includes(n))];
  const data = t.fc.features.map((f) => {
    const row = { ...f.properties };
    if (mode === "wkt") row[geometry] = f.geometry ? geoJSONToWkt(f.geometry) : null;
    if (mode === "lonlat") {
      row[longitude] = f.geometry?.coordinates[0] ?? null;
      row[latitude] = f.geometry?.coordinates[1] ?? null;
    }
    return row;
  });
  return Papa.unparse({ fields, data }, { delimiter: String.fromCharCode(delimiter), header });
}

const results = {};
const failures = [];
function compare(group, label, got, want) {
  const r = (results[group] ??= { cases: 0, bytes: 0, identical: 0, bothRefuse: 0, differ: 0 });
  r.cases++;
  const refused = typeof want !== "string";
  const ok = refused ? typeof got !== "string" : typeof got === "string" && Buffer.compare(encoder.encode(got), encoder.encode(want)) === 0;
  if (!ok) {
    r.differ++;
    if (failures.length < 20) {
      const g = typeof got === "string" ? got : got.error;
      const w = typeof want === "string" ? want : "refused";
      let at = 0;
      while (at < g.length && g[at] === w[at]) at++;
      failures.push({ group, label, at, got: g.slice(Math.max(0, at - 80), at + 120), want: w.slice(Math.max(0, at - 80), at + 120) });
    }
  } else if (refused) r.bothRefuse++;
  else {
    r.identical++;
    r.bytes += encoder.encode(want).length;
  }
}

async function both(group, label, t, csvOptions = [{}]) {
  for (const o of csvOptions) compare(`${group} csv`, `${label} ${JSON.stringify(o)}`, await ours("csv", t, o), theirCsv(t, o));
  compare(`${group} kml`, label, await ours("kml", t), toKML(t.fc));
}

// --- GSI tile features ---
const byLayer = await gsiFeatures({ id: true });
const csvVariants = [{}, { geometryFormat: "wkt" }, { delimiter: 9, header: false }, { delimiter: 59, geometry: "the_geom" }, { geometryFormat: "none" }];
for (const [name, features] of Object.entries(byLayer)) {
  await both("gsi", `${name}: ${features.length} features`, await tableOf({ type: "FeatureCollection", features }), csvVariants);
}
const points = byLayer.label.filter((f) => f.geometry.type === "Point");
await both("gsi", `${points.length} label points`, await tableOf({ type: "FeatureCollection", features: points }), [{}, { longitude: "経度", latitude: "緯度" }, { geometryFormat: "wkt" }]);
const buildings = byLayer.building.filter((f) => f.geometry.type === "Polygon");
const multi = [];
for (let i = 0; i + 1 < buildings.length && i < 400; i += 2) {
  multi.push({ type: "Feature", id: i, properties: { n: i }, geometry: { type: "MultiPolygon", coordinates: [buildings[i].geometry.coordinates, buildings[i + 1].geometry.coordinates] } });
  multi.push({ type: "Feature", properties: { n: -i }, geometry: { type: "MultiPoint", coordinates: [buildings[i].geometry.coordinates[0][0], buildings[i + 1].geometry.coordinates[0][0]] } });
}
await both("gsi", `${multi.length} MultiPolygons and MultiPoints`, await tableOf({ type: "FeatureCollection", features: multi }));

// --- Hand-written cases ---
const P = (coordinates, properties = {}, extra = {}) => ({ type: "Feature", geometry: { type: "Point", coordinates }, properties, ...extra });
const cases = {
  "values that need quotes": [
    P([1, 2], { a: 'say "hi"', b: "x,y", c: "line\nbreak", d: "cr\rhere", e: " lead", f: "trail ", g: "﻿bom", h: "" }),
    P([3, 4], { a: "plain", b: 0, c: -0, d: 1e21, e: 1e-7, f: true, g: false, h: null }),
  ],
  "missing values and rows without geometry": [
    { type: "Feature", geometry: null, properties: {} },
    P([1, 1], { only: "x" }),
    { type: "Feature", geometry: null, properties: { other: 1 } },
  ],
  "a property named like a geometry column": [P([1, 2], { wkt: "kept?", longitude: 9, name: "a" }), P([3, 4], { latitude: 8 })],
  "KML names, descriptions and visibility": [
    P([1, 2], { name: "東京駅", description: "<b>&</b>", visibility: true, note: "]]>", "a&b": 1, 'q"': 2 }, { id: "a<b&\"c" }),
    P([1, 2], { name: 0, description: "", visibility: false }, { id: 7 }),
    P([1, 2], { name: 12.5, description: true, visibility: null, extra: null }, { id: 0 }),
    P([1, 2], { name: false, visibility: 1, empty: "" }),
    P([1, 2], { name: "ctl\u0001\u0007\u000b\u001f\ttab", list: "[1,2]" }),
    P([1, 2], { name: "😀 and \u{20bb7}" }),
  ],
  "every geometry type": [
    { type: "Feature", properties: { k: "line" }, geometry: { type: "LineString", coordinates: [[0, 0], [1, 1], [2, 0.5]] } },
    { type: "Feature", properties: { k: "lines" }, geometry: { type: "MultiLineString", coordinates: [[[0, 0], [1, 1]], [[2, 2], [3, 3]]] } },
    { type: "Feature", properties: { k: "polygon" }, geometry: { type: "Polygon", coordinates: [[[0, 0], [4, 0], [4, 4], [0, 0]], [[1, 1], [1, 2], [2, 2], [1, 1]]] } },
    { type: "Feature", properties: { k: "polygons" }, geometry: { type: "MultiPolygon", coordinates: [[[[0, 0], [1, 0], [1, 1], [0, 0]]], [[[5, 5], [6, 5], [6, 6], [5, 5]]]] } },
    { type: "Feature", properties: { k: "points" }, geometry: { type: "MultiPoint", coordinates: [[1, 2], [3, 4]] } },
    { type: "Feature", properties: { k: "collection" }, geometry: { type: "GeometryCollection", geometries: [{ type: "Point", coordinates: [1, 1] }, { type: "LineString", coordinates: [[0, 0], [1, 1]] }] } },
  ],
  "no rows": [],
};
for (const [label, features] of Object.entries(cases)) {
  await both("cases", label, await tableOf({ type: "FeatureCollection", features }), [{}, { geometryFormat: "wkt" }, { geometryFormat: "none" }, { delimiter: 124 }, { header: false }]);
}
// Numbers JSON cannot hold, from a FlatGeobuf: NaN, infinities, -0 and floats.
const odd = fgbFile(
  [NaN, Infinity, -Infinity, -0, 0.1, 3.4028234663852886e38].map((v, i) => ({ type: "Feature", geometry: { type: "Point", coordinates: [i, i] }, properties: { name: v, v, f: v } })),
  { columns: [{ name: "name", type: T.Double }, { name: "v", type: T.Double }, { name: "f", type: T.Float }] },
);
await both("cases", "NaN, infinities, -0 and floats", await tableOf(odd), [{}, { geometryFormat: "wkt" }]);
const lines = await tableOf({ type: "FeatureCollection", features: cases["every geometry type"] });
compare("refused", "lonlat for lines", await ours("csv", lines, { geometryFormat: "lonlat" }), { error: "not points" });
compare("refused", "a bad geometryFormat", await ours("csv", lines, { geometryFormat: "geojson" }), { error: "bad" });

let differ = 0;
let total = 0;
for (const [group, r] of Object.entries(results)) {
  differ += r.differ;
  total += r.cases;
  console.log(`${group}: ${r.cases} cases, ${r.bytes} bytes identical, ${r.bothRefuse} refused by both, ${r.differ} differ`);
}
for (const f of failures) console.log("DIFF", JSON.stringify(f));
console.log(`${total} cases, ${differ} differ`);
const pkg = async (name) => JSON.parse(await readFile(path.join(ROOT, "bench/node_modules", name, "package.json"), "utf8")).version;
await writeFile(
  path.join(ROOT, "bench/results/write-golden.json"),
  JSON.stringify({ env: { node: process.version, papaparse: await pkg("papaparse"), betterknown: await pkg("betterknown"), "@placemarkio/tokml": await pkg("@placemarkio/tokml"), tiles: GSI_TILES }, results, differ }, null, 2) + "\n",
);
if (differ > 0) process.exit(1);
