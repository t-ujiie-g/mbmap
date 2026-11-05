// data:golden's whole reads (data_worker/js/read.mjs): shapefiles vs shpjs 6.2.0, TopoJSON vs
// topojson-client 3.1.0, SRIDs and `crs` vs proj4 2.22.0. Run by golden.mjs with its helpers.
import { geoJSONToWkt } from "betterknown";
import Papa from "papaparse";
import proj4 from "proj4";
import shp from "shpjs";
import topojsonClient from "topojson-client";
import topojsonServer from "topojson-server";
import wkx from "wkx";
import { readZip } from "../../npm/src/zip.ts";
import { tableToGeoJSON, withIds } from "../../wasmio/js/table.mjs";
import { encodeText, writeShapefile, writeZip } from "./shapefile.mjs";

const encoder = new TextEncoder();
// Coordinates taken from another CRS are compared within this many degrees (proj:golden's bound).
const EPS = 1e-8;

export async function moreCases({ reader, loads, byLayer, geometries, rowsOf, compare, deviation }) {
  // Our rows of a whole read, with `id` where a row has one, or { error }.
  async function ours(format, parts, options = {}) {
    try {
      const r = await reader.read(format, parts, options);
      const fc = tableToGeoJSON(r.table);
      return (r.ids ? withIds(fc, r.ids) : fc).features.map((f) =>
        f.id === undefined ? { geometry: f.geometry, properties: f.properties } : { id: f.id, geometry: f.geometry, properties: f.properties });
    } catch (e) {
      return { error: e.message };
    }
  }
  const layersOf = async (format, parts, options) => {
    const r = await reader.read(format, parts, options);
    return { layer: r.layer, layers: r.layers };
  };

  // --- Shapefiles ---
  const clockwise = (ring) => {
    let sum = 0;
    for (let i = 1; i < ring.length; i++) sum += (ring[i][0] - ring[i - 1][0]) * (ring[i][1] + ring[i - 1][1]);
    return sum > 0;
  };
  const wound = (ring, cw) => (clockwise(ring) === cw ? ring : ring.slice().reverse());
  // Normalization 1: RFC 7946's winding (outer rings counter-clockwise, holes clockwise), which
  // mbmap/data writes; shpjs keeps the shapefile's.
  const rewind = (g) => {
    const poly = (rings) => rings.map((r, i) => wound(r, i > 0));
    return g?.type === "Polygon" ? { ...g, coordinates: poly(g.coordinates) } : g?.type === "MultiPolygon" ? { ...g, coordinates: g.coordinates.map(poly) } : g;
  };
  const day = (d) => (Number.isNaN(d.getTime()) ? null : `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`);
  // Normalizations 2-4: blank numbers are null (shpjs: NaN), dates `YYYY-MM-DD` text (shpjs: a
  // local Date), records deleted in the .dbf left out (shpjs keeps them).
  const values = (props) => Object.fromEntries(Object.entries(props).map(([k, v]) => [k, typeof v === "number" && Number.isNaN(v) ? null : v instanceof Date ? day(v) : v]));
  const shpjsRows = (fc, deleted = new Set()) => fc.features.filter((_, i) => !deleted.has(i)).flatMap((f) => rowsOf(rewind(f.geometry), values(f.properties)));

  // GSI features as shapefile records: outer rings clockwise and holes counter-clockwise, as
  // shapefiles have them; buildings also get a hole (their outline shrunk toward its middle).
  const inside = (ring, [x, y]) => {
    let c = false;
    for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      const [xi, yi, xj, yj] = [ring[i][0], ring[i][1], ring[j][0], ring[j][1]];
      if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
    }
    return c;
  };
  const area = (ring) => Math.abs(ring.reduce((s, p, i) => s + (i > 0 ? (p[0] - ring[i - 1][0]) * (p[1] + ring[i - 1][1]) : 0), 0));
  const shpRings = (polygon) => polygon.map((r, i) => wound(r, i === 0));
  const polygonRecords = [];
  for (const f of [...(byLayer.building ?? []).slice(0, 400), ...(byLayer.waterarea ?? [])]) {
    const g = f.geometry;
    const polys = g.type === "Polygon" ? [g.coordinates] : g.type === "MultiPolygon" ? g.coordinates : [];
    if (polys.length === 0 || polys.flat().some((r) => area(r) === 0)) continue;
    const parts = polys.flatMap(shpRings);
    if (polys.length === 1 && polys[0].length === 1 && polygonRecords.length % 3 === 0) {
      const outer = polys[0][0];
      const [xs, ys] = [outer.map((p) => p[0]), outer.map((p) => p[1])];
      const c = [(Math.min(...xs) + Math.max(...xs)) / 2, (Math.min(...ys) + Math.max(...ys)) / 2];
      const hole = outer.map((p) => [c[0] + (p[0] - c[0]) * 0.4, c[1] + (p[1] - c[1]) * 0.4]);
      if (hole.every((p) => inside(outer, p)) && area(hole) > 0) parts.push(wound(hole, false));
    }
    polygonRecords.push({ parts, properties: f.properties });
  }
  for (let i = 0; i + 1 < polygonRecords.length && i < 60; i += 6) {
    polygonRecords.push({ parts: [...polygonRecords[i].parts, ...polygonRecords[i + 1].parts], properties: {} });
  }
  const lineOf = (g) => (g.type === "LineString" ? [g.coordinates] : g.type === "MultiLineString" ? g.coordinates : []);
  const lineRecords = [...(byLayer.road ?? []).slice(0, 400), ...(byLayer.railway ?? []), ...(byLayer.contour ?? []).slice(0, 200)]
    .map((f) => ({ parts: lineOf(f.geometry), properties: f.properties }))
    .filter((r) => r.parts.length > 0);
  const labels = (byLayer.label ?? []).filter((f) => f.geometry.type === "Point");
  const pointRecords = labels.map((f) => ({ parts: [[f.geometry.coordinates]], properties: f.properties }));
  const multiRecords = [];
  for (let i = 0; i + 2 < labels.length; i += 3) multiRecords.push({ parts: [labels.slice(i, i + 3).map((f) => f.geometry.coordinates)], properties: labels[i].properties });
  multiRecords.push({ parts: [[labels[0].geometry.coordinates]], properties: {} });

  const FIELDS = [
    { name: "ftCode", type: "N", length: 10 },
    { name: "name", type: "C", length: 60 },
    { name: "value", type: "F", length: 19, decimals: 11 },
    { name: "flag", type: "L", length: 1 },
    { name: "date", type: "D", length: 8 },
  ];
  const valuesOf = (r, i) => [
    i % 7 === 3 ? null : r.properties.ftCode ?? i,
    String(r.properties.knj ?? r.properties.name ?? "").slice(0, 18),
    r.parts.flat()[0][0],
    "TFYNtfyn"[i % 8],
    `20${String(10 + (i % 15))}${String(1 + (i % 12)).padStart(2, "0")}${String(1 + (i % 28)).padStart(2, "0")}`,
  ];
  // `nulls`: every 13th record a null shape; `deleted`: every 11th deleted in the .dbf.
  const records = (list, { nulls = false, deleted = false } = {}) => list.map((r, i) => ({
    parts: nulls && i % 13 === 5 ? null : r.parts,
    values: valuesOf(r, i),
    deleted: deleted && i % 11 === 4,
  }));
  const deletedOf = (recs) => new Set(recs.flatMap((r, i) => (r.deleted ? [i] : [])));
  const KINDS = [["points", 1, pointRecords], ["multipoints", 8, multiRecords], ["lines", 3, lineRecords], ["polygons", 5, polygonRecords]];
  for (const [label, base, list] of KINDS) {
    for (const [dims, add] of [["XY", 0], ["Z", 10], ["M", 20]]) {
      const recs = records(list, { nulls: dims === "XY", deleted: dims !== "M" });
      const files = writeShapefile(recs, { type: base + add, fields: FIELDS });
      compare("shapefile", `${recs.length} GSI ${label}, ${dims}`, await ours("shapefile", { shp: files.shp, dbf: files.dbf }), shpjsRows(await shp({ shp: files.shp, dbf: files.dbf }), deletedOf(recs)));
    }
  }
  const lineFiles = writeShapefile(records(lineRecords), { type: 3, fields: FIELDS });
  compare("shapefile", "lines without a .dbf", await ours("shapefile", { shp: lineFiles.shp }), shpjsRows(await shp({ shp: lineFiles.shp })));

  // Text in Shift_JIS: the encoding from a .cpg in its several spellings, the language driver, or
  // the option; shpjs is given a .cpg it understands (its decoder takes WHATWG labels only).
  const sjisFields = [{ name: "名前", type: "C", length: 40 }, { name: "かな", type: "C", length: 60 }, { name: "ftCode", type: "N", length: 6 }];
  const encodable = (t) => {
    try {
      return encodeText(t, "shift_jis") !== null;
    } catch {
      return false;
    }
  };
  const sjisRecs = pointRecords
    .map((r) => ({ parts: r.parts, values: [String(r.properties.knj ?? "").slice(0, 18), String(r.properties.kana ?? "").slice(0, 28), r.properties.ftCode ?? null] }))
    .filter((r) => encodable(r.values[0] + r.values[1]));
  const sjis = writeShapefile(sjisRecs, { type: 1, fields: sjisFields, encoding: "shift_jis", ldid: 0x13 });
  const reference = shpjsRows(await shp({ shp: sjis.shp, dbf: sjis.dbf, cpg: "Shift_JIS" }));
  for (const cpg of ["SJIS", "CP932", "ANSI 932", "Shift_JIS", "932\r\n", null]) {
    const parts = { shp: sjis.shp, dbf: sjis.dbf, ...(cpg === null ? {} : { cpg: encoder.encode(cpg) }) };
    compare("shapefile encodings", `Shift_JIS, .cpg ${cpg === null ? "none (language driver 0x13)" : JSON.stringify(cpg)}`, await ours("shapefile", parts), reference);
  }
  const noDriver = writeShapefile(sjisRecs, { type: 1, fields: sjisFields, encoding: "shift_jis" });
  compare("shapefile encodings", "Shift_JIS by the encoding option", await ours("shapefile", { shp: noDriver.shp, dbf: noDriver.dbf }, { encoding: "shift_jis" }), reference);

  // .prj in Esri and OGC WKT: JGD2011 plane rectangular IX and WGS 84 UTM 54N.
  const ORIGIN_IX = 139 + 50 / 60;
  proj4.defs("EPSG:6677", `+proj=tmerc +lat_0=36 +lon_0=${ORIGIN_IX} +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs`);
  proj4.defs("EPSG:32654", "+proj=utm +zone=54 +datum=WGS84 +units=m +no_defs");
  const PRJ = {
    "Esri JGD2011 IX": `PROJCS["JGD_2011_Japan_Zone_9",GEOGCS["GCS_JGD_2011",DATUM["D_JGD_2011",SPHEROID["GRS_1980",6378137.0,298.257222101]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],PROJECTION["Transverse_Mercator"],PARAMETER["False_Easting",0.0],PARAMETER["False_Northing",0.0],PARAMETER["Central_Meridian",${ORIGIN_IX}],PARAMETER["Scale_Factor",0.9999],PARAMETER["Latitude_Of_Origin",36.0],UNIT["Meter",1.0]]`,
    "OGC EPSG:6677": `PROJCS["JGD2011 / Japan Plane Rectangular CS IX",GEOGCS["JGD2011",DATUM["Japanese_Geodetic_Datum_2011",SPHEROID["GRS 1980",6378137,298.257222101,AUTHORITY["EPSG","7019"]],TOWGS84[0,0,0,0,0,0,0],AUTHORITY["EPSG","1128"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","6668"]],PROJECTION["Transverse_Mercator"],PARAMETER["latitude_of_origin",36],PARAMETER["central_meridian",${ORIGIN_IX}],PARAMETER["scale_factor",0.9999],PARAMETER["false_easting",0],PARAMETER["false_northing",0],UNIT["metre",1,AUTHORITY["EPSG","9001"]],AXIS["Easting",EAST],AXIS["Northing",NORTH],AUTHORITY["EPSG","6677"]]`,
    "Esri WGS 84 UTM 54N": `PROJCS["WGS_1984_UTM_Zone_54N",GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],PROJECTION["Transverse_Mercator"],PARAMETER["False_Easting",500000.0],PARAMETER["False_Northing",0.0],PARAMETER["Central_Meridian",141.0],PARAMETER["Scale_Factor",0.9996],PARAMETER["Latitude_Of_Origin",0.0],UNIT["Meter",1.0]]`,
  };
  const CODE = { "Esri JGD2011 IX": 6677, "OGC EPSG:6677": 6677, "Esri WGS 84 UTM 54N": 32654 };
  const projected = (list, code) => list.map((r) => ({ ...r, parts: r.parts.map((part) => part.map((p) => proj4("EPSG:4326", `EPSG:${code}`, p))) }));
  const projectedFiles = {};
  for (const [name, wkt] of Object.entries(PRJ)) {
    for (const [label, base, list] of KINDS) {
      const files = writeShapefile(records(projected(list, CODE[name])), { type: base, fields: FIELDS });
      projectedFiles[`${name} ${label}`] = { ...files, prj: encoder.encode(wkt) };
      compare("shapefile .prj", `${name}, ${label}`, await ours("shapefile", { shp: files.shp, dbf: files.dbf, prj: encoder.encode(wkt) }), shpjsRows(await shp({ shp: files.shp, dbf: files.dbf, prj: wkt })), EPS);
    }
  }
  const prjLoads = loads.prj;
  const ix = projectedFiles["Esri JGD2011 IX polygons"];
  compare("shapefile .prj", "polygons in plane IX by the crs option (EPSG:6677), no .prj", await ours("shapefile", { shp: ix.shp, dbf: ix.dbf }, { crs: 6677 }), shpjsRows(await shp({ shp: ix.shp, dbf: ix.dbf, prj: PRJ["OGC EPSG:6677"] })), EPS);
  deviation("shapefile .prj", "the crs option leaves the .prj parser unloaded", loads.prj === prjLoads ? [] : { error: "loaded" }, false, "a crs given in place of the .prj needs no WKT parser");

  // Zip archives: the first shapefile by default, another by name; stored and deflated entries.
  const pointFiles = writeShapefile(records(pointRecords), { type: 1, fields: FIELDS });
  const zipped = (method) => writeZip([
    { name: "__MACOSX/gsi/._polygons.shp", data: new Uint8Array(8), method },
    { name: "gsi/polygons.shp", data: ix.shp, method },
    { name: "gsi/polygons.shx", data: ix.shx, method },
    { name: "gsi/polygons.dbf", data: ix.dbf, method },
    { name: "gsi/polygons.prj", data: ix.prj, method },
    { name: "points.SHP", data: pointFiles.shp, method },
    { name: "points.dbf", data: pointFiles.dbf, method },
    { name: "readme.txt", data: encoder.encode("GSI"), method },
  ]);
  for (const method of [8, 0]) {
    const zip = zipped(method);
    const theirs = await shp(zip.slice());
    const byName = Object.fromEntries((Array.isArray(theirs) ? theirs : [theirs]).map((fc) => [fc.fileName, fc]));
    const kind = method === 8 ? "deflated" : "stored";
    compare("shapefile zip", `${kind}: the first shapefile (with its .prj)`, await ours("shapefile", { data: zip }), shpjsRows(byName["gsi/polygons"]), EPS);
    compare("shapefile zip", `${kind}: "points" by name`, await ours("shapefile", { data: zip }, { layer: "points" }), shpjsRows(byName.points));
    compare("shapefile zip", `${kind}: "gsi/polygons" by its path`, await ours("shapefile", { data: zip }, { layer: "gsi/polygons" }), shpjsRows(byName["gsi/polygons"]), EPS);
  }
  const layers = await layersOf("shapefile", { data: zipped(8) }, {});
  deviation("shapefile zip", "layers listed", JSON.stringify(layers) === JSON.stringify({ layer: "gsi/polygons", layers: ["gsi/polygons", "points"] }) ? [] : { error: JSON.stringify(layers) }, false, "the layers of an archive are its .shp files outside __MACOSX, in archive order");
  const one = [{ name: "a.shp", data: pointFiles.shp }];
  for (const [label, zip, pattern] of [
    ["an encrypted entry", writeZip([{ ...one[0], flags: 1 }]), /encrypted/],
    ["compression method 12", writeZip([{ ...one[0], method: 0, writtenMethod: 12 }]), /method 12/],
    ["an entry larger than the cap", writeZip([{ ...one[0], size: 300 * 1024 * 1024 }]), /inflates to more than/],
    ["an entry that inflates past its size", writeZip([{ ...one[0], size: 100 }]), /inflates past/],
    ["no shapefile", writeZip([{ name: "a.txt", data: encoder.encode("x") }]), /no shapefile/],
    ["a missing layer", writeZip(one), /no shapefile named nope/],
    ["not an archive", encoder.encode("PK\x03\x04 no end"), /not a zip archive/],
  ]) {
    const got = await ours("shapefile", { data: zip }, label === "a missing layer" ? { layer: "nope" } : {});
    deviation("shapefile zip refused", label, pattern.test(got.error ?? "") ? got : { ok: got }, true, "refused by mbmap/data's zip reader (shpjs not asked)");
  }
  const capped = readZip(writeZip(one), { bytes: 100 });
  deviation("shapefile zip refused", "a cap on inflated bytes", await capped.read(capped.entries[0]).then(() => [], (e) => ({ error: e.message })), true, "readZip's `bytes` limit holds across reads");

  // Hole assignment by point in ring: H lies in A, but B (listed first) has a box around H too; shpjs
  // (boxes only) gives H to B.
  const A = [[0, 0], [0, 10], [2, 10], [2, 2], [8, 2], [8, 10], [10, 10], [10, 0], [0, 0]];
  const B = [[-3, 5], [-3, 13], [5, 13], [5, 5], [3, 5], [3, 11], [-1, 11], [-1, 5], [-3, 5]];
  const H = [[0.5, 6], [1.5, 6], [1.5, 7], [0.5, 7], [0.5, 6]];
  const holes = writeShapefile([{ parts: [B, A, H], values: [] }], { type: 5 });
  const holeRows = await ours("shapefile", { shp: holes.shp });
  const expected = [{ geometry: { type: "MultiPolygon", coordinates: [[wound(B, false)], [wound(A, false), wound(H, true)]] }, properties: {} }];
  const theirs = shpjsRows(await shp({ shp: holes.shp }));
  deviation("shapefile", "a hole inside one outer ring and another's box", JSON.stringify(holeRows) === JSON.stringify(expected) && JSON.stringify(theirs) !== JSON.stringify(expected) ? [] : { error: JSON.stringify(holeRows) }, false, "mbmap/data gives a hole to the smallest outer ring that contains it (point in ring); shpjs compares bounding boxes only");
  // Rings that all run counter-clockwise (outer rings the wrong way) read as shpjs reads them.
  const ccw = writeShapefile([{ parts: [wound(A, false), wound(H, true)], values: [] }], { type: 5 });
  compare("shapefile", "outer rings counter-clockwise, holes clockwise", await ours("shapefile", { shp: ccw.shp }), shpjsRows(await shp({ shp: ccw.shp })));
  const multipatch = writeShapefile([], { type: 31 });
  deviation("shapefile", "MultiPatch", await ours("shapefile", { shp: multipatch.shp }), true, "MultiPatch shapes are refused");
  deviation("shapefile", "a record past the end", await ours("shapefile", { shp: pointFiles.shp.subarray(0, pointFiles.shp.length - 3) }), true, "shpjs stops at a record cut short; mbmap/data refuses the file");
  const unknownLogical = writeShapefile([{ parts: [[[1, 2]]], values: ["?"] }], { type: 1, fields: [{ name: "flag", type: "L", length: 1 }] });
  deviation("shapefile", "a logical field of ?", JSON.stringify(await ours("shapefile", unknownLogical)) === JSON.stringify([{ geometry: { type: "Point", coordinates: [1, 2] }, properties: { flag: null } }]) ? [] : { error: "not null" }, false, "a logical that is neither true nor false is null; shpjs makes it false");

  // --- TopoJSON ---
  // Nested property values are JSON text in mbmap/data's tables.
  const flat = (props) => Object.fromEntries(Object.entries(props ?? {}).map(([k, v]) => [k, v !== null && typeof v === "object" ? JSON.stringify(v) : v]));
  const topoRows = (topology, name) => {
    const fc = topojsonClient.feature(topology, topology.objects[name]);
    return (fc.type === "FeatureCollection" ? fc.features : [fc]).flatMap((f) =>
      rowsOf(f.geometry, flat(f.properties)).map((r) => (f.id == null ? r : { id: f.id, ...r })));
  };
  const topoText = (t) => encoder.encode(JSON.stringify(t));
  const collection = (list, ids) => ({ type: "FeatureCollection", features: list.map((f, i) => (ids ? { ...f, id: i % 3 === 0 ? `f${i}` : i } : f)) });
  const objects = {
    buildings: collection((byLayer.building ?? []).slice(0, 300)),
    roads: collection((byLayer.road ?? []).slice(0, 300)),
    labels: collection(labels.slice(0, 300), true),
  };
  for (const q of [0, 1e4, 1e6]) {
    const topology = topojsonServer.topology(objects, q || undefined);
    for (const name of Object.keys(topology.objects)) {
      compare("topojson", `GSI ${name}, ${q ? `quantized ${q}` : "not quantized"}`, await ours("topojson", { data: topoText(topology) }, { layer: name }), topoRows(topology, name));
    }
    compare("topojson", `GSI, the first object, ${q || "not quantized"}`, await ours("topojson", { data: topoText(topology) }), topoRows(topology, "buildings"));
  }
  const HAND = {
    type: "Topology",
    transform: { scale: [0.5, 0.25], translate: [100, 10] },
    arcs: [[[0, 0], [2, 0], [0, 2]], [[2, 2], [-2, 0], [0, -2]], [[4, 4], [2, 2]], [[8, 8]]],
    objects: {
      collection: {
        type: "GeometryCollection",
        geometries: [
          { type: "LineString", arcs: [0, 1], id: "a", properties: { n: 1, nested: { x: [1, 2] }, s: "テキスト" } },
          { type: "LineString", arcs: [~1, ~0], id: 2 },
          { type: "Polygon", arcs: [[0, 1]], id: null },
          { type: "Point", coordinates: [4, 8], properties: { kind: "pt" } },
          { type: "MultiPoint", coordinates: [[0, 0], [2, 4]] },
          { type: null, properties: { empty: true } },
          { type: "GeometryCollection", geometries: [{ type: "Point", coordinates: [1, 1] }, { type: "LineString", arcs: [2] }], properties: { gc: 1 } },
          { type: "MultiLineString", arcs: [[0], [~2]], bbox: [0, 0, 1, 1] },
          { type: "MultiPolygon", arcs: [[[2]], [[0, 1]]] },
          { type: "Polygon", arcs: [[2]] },
          { type: "LineString", arcs: [3] },
          { type: "Unknown", arcs: [0], properties: { u: true } },
        ],
      },
      single: { type: "LineString", arcs: [2], id: 7, properties: { one: 1 } },
    },
  };
  const untransformed = { ...HAND, transform: undefined, arcs: [[[139.5, 35.5], [139.75, 35.5], [139.75, 35.75]], [[139.75, 35.75], [139.5, 35.75], [139.5, 35.5]], [[140, 36], [140.25, 36.25]], [[141, 37]]] };
  for (const [label, t] of [["hand-made, quantized", HAND], ["hand-made, not quantized", untransformed]]) {
    for (const name of ["collection", "single"]) compare("topojson", `${label}: ${name}`, await ours("topojson", { data: topoText(t) }, { layer: name }), topoRows(t, name));
  }
  const listed = await layersOf("topojson", { data: topoText(HAND) }, {});
  deviation("topojson", "objects listed", JSON.stringify(listed) === JSON.stringify({ layer: "collection", layers: ["collection", "single"] }) ? [] : { error: JSON.stringify(listed) }, false, "a topology's objects are its layers, in order");
  const refuse = (t, options) => ours("topojson", { data: typeof t === "string" ? encoder.encode(t) : topoText(t) }, options);
  const both = async (label, t, options, theirs) => {
    let want = null;
    try {
      want = theirs();
    } catch {
      want = null;
    }
    compare("topojson refused", label, await refuse(t, options), want);
  };
  await both("an arc index out of range", { ...HAND, objects: { o: { type: "LineString", arcs: [9] } } }, {}, () => topoRows({ ...HAND, objects: { o: { type: "LineString", arcs: [9] } } }, "o"));
  await both("an unknown object", HAND, { layer: "nope" }, () => topoRows(HAND, "nope"));
  await both("not JSON", "{\"type\": \"Topology\", ", {}, () => JSON.parse("{\"type\": \"Topology\", "));
  deviation("topojson", "a GeoJSON object", await refuse({ type: "FeatureCollection", features: [] }), true, "only a Topology is read (topojson-client reads any object with arcs and objects)");

  // --- SRIDs and the crs option ---
  const cycle = [6677, 3857, 32654, 4326, 0];
  const mapGeometry = (g, f) => {
    const m = (c) => (typeof c[0] === "number" ? f(c) : c.map(m));
    return g.type === "GeometryCollection" ? { ...g, geometries: g.geometries.map((x) => mapGeometry(x, f)) } : { ...g, coordinates: m(g.coordinates) };
  };
  const sample = geometries.filter((_, i) => i % 9 === 0).slice(0, 400);
  const tagged = sample.map((g, i) => {
    const srid = cycle[i % cycle.length];
    const code = srid === 0 ? 4326 : srid;
    const p = code === 4326 ? g : mapGeometry(g, (c) => proj4("EPSG:4326", `EPSG:${code}`, c));
    return { srid, projected: p, back: code === 4326 ? g : mapGeometry(p, (c) => proj4(`EPSG:${code}`, "EPSG:4326", c)) };
  });
  const wanted = (props) => tagged.flatMap((t, i) => rowsOf(t.back, props?.(i)));
  const ewkt = tagged.map((t) => `${t.srid ? `SRID=${t.srid};` : ""}${geoJSONToWkt(t.projected)}`);
  compare("srid", `${ewkt.length} EWKT geometries in SRIDs 6677, 3857, 32654, 4326 and none`, await ours("wkt", { data: encoder.encode(ewkt.join("\n")) }), wanted(), EPS);
  const ewkb = tagged.map((t) => {
    const x = wkx.Geometry.parseGeoJSON(t.projected);
    if (t.srid) x.srid = t.srid;
    return Uint8Array.from(t.srid ? x.toEwkb() : x.toWkb());
  });
  const joined = new Uint8Array(ewkb.reduce((s, b) => s + b.length, 0));
  ewkb.reduce((at, b) => (joined.set(b, at), at + b.length), 0);
  compare("srid", `${ewkb.length} EWKB geometries, mixed SRIDs`, await ours("wkb", { data: joined }), wanted(), EPS);
  const wktCsv = Papa.unparse(ewkt.map((WKT, i) => ({ i, WKT })));
  compare("srid", `${ewkt.length} EWKT cells of a CSV`, await ours("csv", { data: encoder.encode(wktCsv) }), wanted((i) => ({ i })), EPS);
  const hexCsv = Papa.unparse(ewkb.map((b, i) => ({ i, geom: Buffer.from(b).toString("hex") })));
  compare("srid", `${ewkb.length} hex EWKB cells of a CSV`, await ours("csv", { data: encoder.encode(hexCsv) }), wanted((i) => ({ i })), EPS);
  const plane = labels.slice(0, 300).map((f) => ({ name: f.properties.knj ?? "", ...Object.fromEntries(["x", "y"].map((k, j) => [k, proj4("EPSG:4326", "EPSG:6677", f.geometry.coordinates)[j]])) }));
  const planeRows = plane.map((r) => ({ geometry: { type: "Point", coordinates: proj4("EPSG:6677", "EPSG:4326", [r.x, r.y]) }, properties: r }));
  compare("srid", `${plane.length} CSV x, y in plane IX by the crs option`, await ours("csv", { data: encoder.encode(Papa.unparse(plane)) }, { crs: 6677 }), planeRows, EPS);
  const untagged = tagged.filter((t) => t.srid === 0 || t.srid === 3857).map((t, i) => {
    if (i % 2 === 0) return { text: `SRID=4326;${geoJSONToWkt(t.back)}`, want: t.back };
    const p = t.srid === 3857 ? t.projected : mapGeometry(t.back, (c) => proj4("EPSG:4326", "EPSG:3857", c));
    return { text: geoJSONToWkt(p), want: mapGeometry(p, (c) => proj4("EPSG:3857", "EPSG:4326", c)) };
  });
  const mixed = untagged.map((u) => u.text);
  const mixedRows = untagged.flatMap((u) => rowsOf(u.want));
  compare("srid", "WKT without an SRID by the crs option (3857), SRID 4326 rows kept", await ours("wkt", { data: encoder.encode(mixed.join("\n")) }, { crs: 3857 }), mixedRows, EPS);
  const before = loads.proj;
  await ours("wkt", { data: encoder.encode("SRID=4326;POINT (1 2) POINT (3 4)") });
  deviation("srid", "4326 alone leaves proj.wasm unloaded", loads.proj === before ? [] : { error: "loaded" }, false, "only rows in another CRS load the coordinate system module");
  const unknown = await ours("wkt", { data: encoder.encode("SRID=9999;POINT (1 2)") });
  deviation("srid", "SRID 9999", /SRID 9999: unsupported CRS EPSG:9999/.test(unknown.error ?? "") ? unknown : { ok: unknown }, true, "SRIDs proj.wasm does not know are refused");
}
