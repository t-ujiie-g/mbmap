// The data worker's reads (docs/FORMATS.md "Data worker messages") on bytes already
// fetched, apart from its messages so that bench/data/golden.mjs runs them in Node.

import { hostNumber, MAX_INPUT_BYTES } from "../../wasmio/js/host.mjs";
import { fetchInit, readCapped } from "../../worker/js/body.mjs";
import { readString } from "../../worker/js/values.mjs";

// The zip reader and the CRS conversion, imported with the first archive and the first data
// in another CRS (npm/scripts/build.mjs makes them files of their own).
const zipModule = () => import("../../npm/src/zip.ts");
const crsModule = () => import("./crs.mjs");
const fgbModule = () => import("./fgb.mjs");
const geotiffModule = () => import("./geotiff.mjs");
const lonLat = (crs) => crs === undefined || crs === 4326;

const decoder = new TextDecoder();
const encoder = new TextEncoder();

// Code pages by number (a .cpg's `936`, `CP932`, `ANSI 1252`) and by DBF language driver id.
const CODE_PAGES = { 932: "shift_jis", 936: "gbk", 949: "euc-kr", 950: "big5", 866: "ibm866", 874: "windows-874", 20932: "euc-jp", 65001: "utf-8" };
const DRIVERS = { 3: 1252, 0x13: 932, 0x26: 866, 0x4d: 936, 0x4e: 949, 0x4f: 950, 0x50: 874, 0x58: 1252, 0x59: 1252, 0x65: 866, 0x78: 950, 0x79: 949, 0x7a: 936, 0x7b: 932, 0x7c: 874, 0x7d: 1255, 0x7e: 1256, 0xc8: 1250, 0xc9: 1251, 0xca: 1254, 0xcb: 1253, 0xcc: 1257 };

function codePage(n) {
  return CODE_PAGES[n] ?? (n >= 1250 && n <= 1258 ? `windows-${n}` : n >= 28591 && n <= 28606 ? `iso-8859-${n - 28590}` : undefined);
}

const label = (name) => {
  try {
    return new TextDecoder(name).encoding;
  } catch {
    return undefined;
  }
};

/**
 * The encoding of a DBF's text: `given` (an option), else its .cpg (`cpg`: a WHATWG label or a code
 * page), else its language driver id (byte 29), else UTF-8.
 */
export function dbfEncoding(given, cpg, dbf) {
  for (const name of [given, cpg?.trim().split(/\r?\n/)[0].trim()]) {
    if (!name) continue;
    const m = /^(?:ANSI|CP|MS|WINDOWS-?|IBM)?\s*(\d+)$/i.exec(name);
    const found = m ? codePage(Number(m[1])) : label(name);
    if (found) return label(found) ?? "utf-8";
  }
  return (dbf && dbf.length > 29 && codePage(DRIVERS[dbf[29]])) || "utf-8";
}

/**
 * The imports of data.wasm: `host.number`, `host.decode` / `host.text_code` (DBF text in
 * `encoding`) and `host.number_text` (`String(x)`, read back by `text_code`).
 */
export function dataImports(memory) {
  let text = "";
  const host = {
    number: hostNumber(memory),
    decoder: new TextDecoder(),
    decode(addr, len) {
      text = host.decoder.decode(new Uint8Array(memory().buffer, addr, len)).replace(/\0/g, "").trim();
      return text.length;
    },
    text_code: (i) => text.charCodeAt(i),
    number_text(x) {
      text = String(x);
      return text.length;
    },
  };
  return { host };
}

function input(wasm, parts) {
  const len = parts.reduce((s, b) => s + b.length, 0);
  const addr = wasm.prepare_input(len);
  if (addr < 0) throw new Error(`input too large (${len} bytes)`);
  let at = addr;
  for (const b of parts) {
    new Uint8Array(wasm.memory.buffer, at, b.length).set(b);
    at += b.length;
  }
}

function output(wasm, n) {
  if (n === -2) throw new Error("out of memory");
  const at = wasm.output_addr();
  if (n < 0) throw new Error(decoder.decode(new Uint8Array(wasm.memory.buffer, at, -n)));
  return wasm.memory.buffer.slice(at, at + n);
}

const isName = (n) => n === undefined || (typeof n === "string" && n.length > 0 && !n.includes("\0"));

/** Whether `bytes` start as a zip archive does (a local header, or the end of an empty one). */
export const isZip = (b) => b.length >= 4 && b[0] === 0x50 && b[1] === 0x4b && (b[2] === 3 || b[2] === 5);

/** The KML of the KMZ `bytes`: `doc.kml` at its top, else its first `.kml` entry, at most `max` bytes. */
export async function kmlOfKmz(bytes, max = MAX_INPUT_BYTES) {
  const { entries, read } = (await zipModule()).readZip(bytes, { bytes: max });
  const kml = entries.filter((e) => /\.kml$/i.test(e.name));
  const entry = kml.find((e) => e.name.toLowerCase() === "doc.kml") ?? kml[0];
  if (!entry) throw new Error("the KMZ holds no .kml file");
  return read(entry);
}

// A source of a file's bytes for `readRaster`: `bytes`, a Blob read in slices, or `url` by range
// requests (`init` as worker/js/body.mjs's `fetchInit` takes it), at most `max` bytes in all.
export function rasterSource({ bytes, blob, url, init }, max) {
  if (bytes) return { bytes };
  if (blob) return { read: async (offset, length) => new Uint8Array(await blob.slice(offset, offset + length).arrayBuffer()) };
  return {
    key: url,
    async read(offset, length) {
      const options = fetchInit(init);
      options.headers = { ...options.headers, Range: `bytes=${offset}-${offset + length - 1}` };
      const res = await fetch(url, options);
      if (res.status === 200) return { whole: await readCapped(res, max) };
      if (res.status !== 206) throw new Error(`HTTP ${res.status} for ${url}`);
      if (!res.headers.get("content-range")?.startsWith(`bytes ${offset}-`)) throw new Error(`${url} answered another range`);
      return readCapped(res, length);
    },
  };
}

/** A reader over data.wasm (`imports` from `dataImports`): `read`, `write` and `readRaster` as the worker's messages;
 * `proj()`, `prj()`, `xml()` and `geotiff()` load proj.wasm, npm/src/prjwkt.ts, xml.wasm and geotiff.wasm on first use. */
export function dataReader(wasm, imports, { proj, prj, xml, geotiff }) {
  async function shapefile(files, options) {
    const { shp, dbf, cpg, prj: prjBytes } = files;
    if (!shp) throw new Error("no .shp");
    imports.host.decoder = new TextDecoder(dbfEncoding(options.encoding, cpg && decoder.decode(cpg), dbf));
    input(wasm, dbf ? [shp, dbf] : [shp]);
    const table = output(wasm, wasm.read_shapefile(shp.length, dbf?.length ?? 0));
    let crs = options.crs;
    const text = prjBytes && decoder.decode(prjBytes).trim();
    if (crs === undefined && text) crs = (await prj()).parsePrj(text);
    return { table, crs };
  }

  async function zip(bytes, options) {
    const { entries, read: inflate } = (await zipModule()).readZip(bytes);
    const stem = (e) => e.name.replace(/\.[^./]*$/, "");
    const shps = entries.filter((e) => /\.shp$/i.test(e.name) && !/(^|\/)(__MACOSX\/|\._)/.test(e.name));
    if (shps.length === 0) throw new Error("no shapefile in the archive");
    const layers = shps.map(stem);
    const at = options.layer === undefined ? 0 : layers.findIndex((l) => l === options.layer || l.split("/").pop() === options.layer);
    if (at < 0) throw new Error(`no shapefile named ${options.layer} in the archive (it has ${layers.join(", ")})`);
    const files = {};
    for (const e of entries) {
      const ext = /\.(shp|dbf|prj|cpg)$/i.exec(e.name)?.[1].toLowerCase();
      if (ext && stem(e).toLowerCase() === layers[at].toLowerCase()) files[ext] ??= await inflate(e);
    }
    return { ...(await shapefile(files, options)), layer: layers[at], layers };
  }

  // KML and GPX are in EPSG:4326 by definition, so they skip the CRS step.
  async function xmlRead(format, data, options) {
    if (options.crs !== undefined) throw new Error("KML and GPX are always in EPSG:4326");
    const kml = format === "kml" && isZip(data) ? await kmlOfKmz(data) : data;
    const x = await xml();
    input(x, [kml]);
    const table = output(x, format === "kml" ? x.read_kml() : x.read_gpx());
    const ids = x.ids_out();
    return { table, ids: ids > 0 ? output(x, ids) : null, layer: null, layers: [] };
  }

  // The whole file, or with `bbox` the features its index finds there: in `data`, or by range
  // requests to `parts.remote` ({ url, init }).
  async function flatgeobuf({ data, remote }, options) {
    const fgb = await fgbModule();
    const { bbox } = options;
    const { bytes, ids } =
      remote ? await fgb.selectUrl(remote.url, remote.init, bbox, MAX_INPUT_BYTES, { fetchInit, readCapped }) :
      bbox !== undefined ? await fgb.selectBytes(data, bbox) :
      { bytes: data, ids: -1 };
    const header = fgb.readHeader(bytes);
    input(wasm, [bytes]);
    const table = output(wasm, wasm.read_flatgeobuf(ids));
    let crs = options.crs ?? fgb.headerCrs(header.crs);
    if (crs?.wkt) crs = (await prj()).parsePrj(crs.wkt);
    const n = wasm.ids_out();
    return { table, ids: n > 0 ? output(wasm, n) : null, crs };
  }

  async function read(format, parts, options) {
    let result;
    const { data } = parts;
    if (format === "kml" || format === "gpx") return xmlRead(format, data, options);
    if (format === "geojson") {
      if (options.crs !== undefined) throw new Error("GeoJSON is always in EPSG:4326");
      input(wasm, [data]);
      const table = output(wasm, wasm.read_geojson());
      const ids = wasm.ids_out();
      return { table, ids: ids > 0 ? output(wasm, ids) : null, layer: null, layers: [] };
    }
    if (format === "flatgeobuf") {
      result = await flatgeobuf(parts, options);
    } else if (format === "shapefile") {
      result = data && isZip(data) ? await zip(data, options) : await shapefile(data ? { shp: data } : parts, options);
    } else if (format === "topojson") {
      const name = options.layer === undefined ? new Uint8Array(0) : encoder.encode(options.layer);
      input(wasm, [name, data]);
      const table = output(wasm, wasm.read_topojson(options.layer === undefined ? -1 : name.length));
      const v = new DataView(output(wasm, wasm.layers_out()));
      const bytes = new Uint8Array(v.buffer);
      const layers = [];
      for (let at = 0; at < bytes.length;) {
        const [s, next] = readString(v, bytes, at);
        layers.push(s);
        at = next;
      }
      const ids = wasm.ids_out();
      result = { table, ids: ids > 0 ? output(wasm, ids) : null, layer: options.layer ?? layers[0] ?? null, layers };
    } else if (format === "wkt" || format === "wkb") {
      input(wasm, [data]);
      result = { table: output(wasm, format === "wkt" ? wasm.read_wkt() : wasm.read_wkb()) };
    } else {
      const { delimiter = -1, header = true, dynamicTyping = true, latitude, longitude, geometry } = options;
      if (!Number.isInteger(delimiter) || typeof header !== "boolean" || typeof dynamicTyping !== "boolean") throw new Error("invalid arguments");
      if (![latitude, longitude, geometry].every(isName)) throw new Error("invalid arguments");
      const names = encoder.encode(`${latitude ?? ""}\0${longitude ?? ""}\0${geometry ?? ""}\0`);
      input(wasm, [names, data]);
      result = { table: output(wasm, wasm.read_csv(names.length, delimiter, header ? 1 : 0, dynamicTyping ? 1 : 0)) };
    }
    const n = wasm.srids_out();
    const srids = n > 0 ? new Int32Array(output(wasm, n * 4)) : null;
    let crs = result.crs ?? options.crs;
    if (crs?.code === 4326) crs = 4326;
    const other = srids ? srids.some((s) => s !== 0 && s !== 4326) || (srids.includes(0) && !lonLat(crs)) : !lonLat(crs);
    if (other) await (await crsModule()).toLonLat(result.table, srids, crs, proj);
    return { table: result.table, ids: result.ids ?? null, layer: result.layer ?? null, layers: result.layers ?? [] };
  }
  /**
   * `table` (and its `ids`, property values, or null) as `format` ("csv" or "kml") in UTF-8;
   * CSV `options` as docs/FORMATS.md "Data worker messages" has them.
   */
  async function write(format, table, ids, options) {
    const t = new Uint8Array(table);
    if (format === "kml") {
      const x = await xml();
      const idBytes = ids ? new Uint8Array(ids) : new Uint8Array(0);
      input(x, [t, idBytes]);
      return output(x, x.write_kml(idBytes.length));
    }
    const { delimiter = 44, header = true, geometry = "wkt", longitude = "longitude", latitude = "latitude" } = options;
    if (!Number.isInteger(delimiter) || typeof header !== "boolean" || ![geometry, longitude, latitude].every(isName)) throw new Error("invalid arguments");
    const mode = ["none", "wkt", "lonlat", undefined].indexOf(options.geometryFormat);
    if (mode < 0) throw new Error("invalid geometryFormat");
    const names = encoder.encode(`${geometry}\0${longitude}\0${latitude}\0`);
    input(wasm, [names, t]);
    return output(wasm, wasm.write_csv(names.length, delimiter, header ? 1 : 0, mode));
  }
  /** A window of the GeoTIFF of `source` (see `rasterSource`) as npm/README.md's `readRaster` gives it. */
  // `op` of data_worker/js/geotiff.mjs over geotiff.wasm.
  async function raster(op, ...args) {
    const [m, g] = await Promise.all([geotiffModule(), geotiff()]);
    const transform = async (from, to, xy) => (await crsModule()).transformPairs(await proj(), from, to, xy);
    return m[op](...args, { wasm: g, input, output, max: MAX_INPUT_BYTES, transform });
  }
  return {
    read,
    write,
    readRaster: (source, options) => raster("readRaster", source, options),
    rasterInfo: (source) => raster("rasterInfo", source),
    rasterTile: (source, options) => raster("renderTile", source, options),
  };
}
