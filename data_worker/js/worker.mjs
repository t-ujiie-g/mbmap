// Glue around the wasm-gc build of `data_worker`; messages are in
// docs/FORMATS.md ("Data worker messages").

import { hostText, MAX_INPUT_BYTES } from "../../wasmio/js/host.mjs";
import { fetchInit, readCapped } from "../../worker/js/body.mjs";
import { dataImports, dataReader, rasterSource } from "./read.mjs";

let reader = null;
let ready = null;
// Reads run one after another: data.wasm keeps a read's results until the next.
let queue = Promise.resolve();
const urls = {};
const loaded = {};
// proj.wasm (with the host's Math, as proj4js computes), the .prj parser and xml.wasm (KML and
// GPX), each on first use.
function load(name, start) {
  if (typeof urls[name] !== "string") return Promise.reject(new Error(`no URL for the ${name} module`));
  return (loaded[name] ??= start(urls[name]));
}
const proj = () => load("proj", (url) => WebAssembly.instantiateStreaming(fetch(url), { Math }).then(({ instance }) => instance.exports));
const prj = () => load("prj", (url) => import(url));
const xml = () => load("xml", (url) => WebAssembly.instantiateStreaming(fetch(url), { Math, host: hostText() }).then(({ instance }) => instance.exports));
const geotiff = () => load("geotiff", (url) => WebAssembly.instantiateStreaming(fetch(url), {}).then(({ instance }) => instance.exports));

function check(ok) {
  if (!ok) throw new Error("invalid arguments");
}

const FORMATS = ["csv", "wkt", "wkb", "shapefile", "topojson", "kml", "gpx", "flatgeobuf", "geojson"];
const PARTS = ["shp", "dbf", "prj", "cpg"];

// A source's bytes: fetched (http(s) only, no credentials unless `init` asks for them; null for
// a 404 if `optional`), a Blob's, or bytes given; at most MAX_INPUT_BYTES.
async function bytesOf({ url, init, blob, bytes }, optional = false) {
  if (bytes instanceof ArrayBuffer) {
    check(bytes.byteLength <= MAX_INPUT_BYTES);
    return new Uint8Array(bytes);
  }
  if (blob instanceof Blob) {
    if (blob.size > MAX_INPUT_BYTES) throw new Error(`data larger than ${MAX_INPUT_BYTES} bytes`);
    return new Uint8Array(await blob.arrayBuffer());
  }
  check(typeof url === "string" && /^https?:/i.test(url));
  const res = await fetch(url, fetchInit(init));
  if (optional && res.status === 404) return null;
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  return readCapped(res, MAX_INPUT_BYTES);
}

async function read(msg) {
  const { format, options = {}, parts } = msg;
  check(FORMATS.includes(format) && options && typeof options === "object");
  const { crs, layer, encoding, bbox } = options;
  check(bbox === undefined || (format === "flatgeobuf" && Array.isArray(bbox) && bbox.length === 4 && bbox.every(Number.isFinite)));
  check(crs === undefined || (Number.isInteger(crs) && crs > 0) || crs instanceof Float64Array);
  check((layer === undefined || typeof layer === "string") && (encoding === undefined || typeof encoding === "string"));
  const files = {};
  if (parts && typeof parts === "object") {
    check(format === "shapefile");
    for (const p of PARTS) if (parts[p]) files[p] = await bytesOf(parts[p]);
  } else if (format === "flatgeobuf" && bbox !== undefined && typeof msg.url === "string") {
    check(/^https?:/i.test(msg.url));
    files.remote = { url: msg.url, init: msg.init };
  } else {
    files.data = await bytesOf(msg);
    // A .shp by URL brings the files beside it that are there.
    const shp = typeof msg.url === "string" && /\.shp$/i.exec(new URL(msg.url).pathname);
    if (format === "shapefile" && shp) {
      const base = new URL(msg.url);
      for (const p of PARTS.slice(1)) {
        base.pathname = base.pathname.slice(0, -3) + p;
        files[p] = await bytesOf({ url: base.href, init: msg.init }, true);
      }
      files.shp = files.data;
      delete files.data;
    }
  }
  return reader.read(format, files, options);
}

async function run(msg) {
  try {
    await ready;
    if (msg.op === "readRaster" || msg.op === "rasterInfo" || msg.op === "rasterTile") {
      const { url, init, blob, bytes, options = {} } = msg;
      check(options && typeof options === "object");
      check(bytes instanceof ArrayBuffer || blob instanceof Blob || (typeof url === "string" && /^https?:/i.test(url)));
      if (bytes) check(bytes.byteLength <= MAX_INPUT_BYTES);
      const source = rasterSource({ bytes: bytes && new Uint8Array(bytes), blob, url, init }, MAX_INPUT_BYTES);
      if (msg.op === "rasterTile") {
        const { z, x, y, tileSize = 256 } = options;
        check([z, x, y].every(Number.isInteger) && z >= 0 && z <= 24 && x >= 0 && y >= 0 && x < 2 ** z && y < 2 ** z && (tileSize === 256 || tileSize === 512));
      }
      const value = await (msg.op === "readRaster" ? reader.readRaster(source, options) : msg.op === "rasterInfo" ? reader.rasterInfo(source) : reader.rasterTile(source, options));
      postMessage({ type: "result", id: msg.id, value }, msg.op === "readRaster" ? [...new Set(value.bands.map((b) => b.buffer))] : value instanceof ArrayBuffer ? [value] : []);
      return;
    }
    if (msg.op === "write") {
      const { format, table, ids = null, options = {} } = msg;
      check(["csv", "kml"].includes(format) && table instanceof ArrayBuffer && (ids === null || ids instanceof ArrayBuffer) && options && typeof options === "object");
      const value = await reader.write(format, table, ids, options);
      postMessage({ type: "result", id: msg.id, value }, [value]);
      return;
    }
    const value = await read(msg);
    postMessage({ type: "result", id: msg.id, value }, [value.table, ...(value.ids ? [value.ids] : [])]);
  } catch (err) {
    postMessage({ type: "result", id: msg.id, error: String(err?.message ?? err) });
  }
}

onmessage = (e) => {
  const msg = e.data;
  if (msg?.type === "init" && !ready && typeof msg.wasm === "string") {
    urls.proj = msg.proj;
    urls.prj = msg.prj;
    urls.xml = msg.xml;
    urls.geotiff = msg.geotiff;
    let wasm = null;
    const imports = dataImports(() => wasm.memory);
    ready = WebAssembly.instantiateStreaming(fetch(msg.wasm), imports).then(({ instance }) => {
      wasm = instance.exports;
      reader = dataReader(wasm, imports, { proj, prj, xml, geotiff });
    });
  } else if (msg?.type === "call" && ready && Number.isInteger(msg.id) && ["read", "write", "readRaster", "rasterInfo", "rasterTile"].includes(msg.op)) {
    queue = queue.then(() => run(msg));
  }
};
