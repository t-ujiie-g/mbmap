// The data worker's reads (docs/FORMATS.md "Data worker messages") on bytes already
// fetched, apart from its messages so that bench/data/golden.mjs runs them in Node.

import { hostNumber } from "../../wasmio/js/host.mjs";
import { readString } from "../../worker/js/values.mjs";

// The zip reader and the CRS conversion, imported with the first archive and the first data
// in another CRS (npm/scripts/build.mjs makes them files of their own).
const zipModule = () => import("../../npm/src/zip.ts");
const crsModule = () => import("./crs.mjs");
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

/** The imports of data.wasm: `host.number` and `host.decode` / `host.text_code`, DBF text in `encoding`. */
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

/**
 * A reader over data.wasm (`imports` from `dataImports`): `read(format, parts, options)` with `parts.data`
 * or a shapefile's `shp`, `dbf`, `prj`, `cpg` bytes gives `{ table, ids, layer, layers }`; `proj()` and
 * `prj()` load proj.wasm's exports and npm/src/prjwkt.ts on first use.
 */
export function dataReader(wasm, imports, { proj, prj }) {
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

  async function read(format, parts, options) {
    let result;
    const { data } = parts;
    if (format === "shapefile") {
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
  return { read };
}
