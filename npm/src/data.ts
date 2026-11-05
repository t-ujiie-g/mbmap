// `mbmap/data`: CSV, WKT, WKB, shapefiles, TopoJSON, KML/KMZ, GPX and FlatGeobuf read in a worker of its own
// (KML and GPX by a second wasm), started on the first call, into tables that are both a GeoJSON
// source's data (`toGeoJSON`) and an mbmap/analysis dataset (`load(table)`).
import { tableInfo, tableToGeoJSON, withIds } from "../../wasmio/js/table.mjs";
import { crsArg, type Crs } from "./crs";
import { bboxArg, csvArgs, csvWriteArgs, formatOf, shapefileParts, type CsvOptions, type CsvWriteOptions, type DataFormat, type ShapefileParts, type WriteFormat } from "./data-format";
import { httpUrl, wasmUrl } from "./urls";
import { WorkerClient } from "./worker-client";

export type { CsvOptions, CsvWriteOptions, DataFormat, ShapefileParts, WriteFormat, Crs };

/** What `DataTable.toGeoJSON` gives: a feature per row, its geometry null without one. */
export interface DataFeatureCollection {
  type: "FeatureCollection";
  features: { type: "Feature"; id?: string | number; geometry: { type: string; coordinates: unknown } | null; properties: Record<string, unknown> }[];
}

/** Where the data worker (`workerUrl`), its wasm (`wasmUrl`), proj.wasm (`projWasmUrl`), xml.wasm (`xmlUrl`) and
 * geotiff.wasm (`geotiffUrl`, each loaded on first use) are served; by default next to this module. */
export interface DataOptions {
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
  projWasmUrl?: string | URL;
  xmlUrl?: string | URL;
  geotiffUrl?: string | URL;
}

/**
 * `format`: the reader (by default from a URL's or a File's name, see `formatOf`); `transformRequest`:
 * may change a URL's request as the map's does (no credentials are sent otherwise). `crs`: the CRS of
 * coordinates the data does not tag (a shapefile's in place of its .prj, rows without an SRID; by
 * default EPSG:4326): rows are taken to longitude and latitude. `layer`: the shapefile of a .zip
 * (its name without `.shp`, with or without folders) or the TopoJSON object to read, by default the
 * first; `encoding`: a .dbf's text encoding (a label such as `"shift_jis"` or a code page), in place
 * of its .cpg and language driver. `bbox`: `[minX, minY, maxX, maxY]` in a FlatGeobuf's coordinates,
 * to read only the features its index finds there (by HTTP range requests from a URL).
 */
export interface ReadOptions extends DataOptions, CsvOptions {
  format?: DataFormat;
  transformRequest?: (url: string) => { url: string; headers?: Record<string, string>; credentials?: RequestCredentials } | undefined;
  crs?: Crs;
  layer?: string;
  encoding?: string;
  bbox?: [number, number, number, number];
}

/** A read's result as the data worker gives it (docs/FORMATS.md "Data worker messages"). */
interface ReadResult {
  table: ArrayBuffer;
  ids: ArrayBuffer | null;
  layer: string | null;
  layers: string[];
}

/**
 * Rows read by `read` or `parse`: `length` rows (a geometry collection makes one per member),
 * `columns` the property keys, `layer` the shapefile or TopoJSON object read and `layers` the input's.
 */
export class DataTable {
  readonly format: DataFormat;
  readonly length: number;
  readonly columns: readonly string[];
  readonly layer: string | null;
  readonly layers: readonly string[];
  #bytes: ArrayBuffer;
  #ids: ArrayBuffer | null;

  /** @internal */
  constructor(format: DataFormat, result: ReadResult) {
    const { length, columns } = tableInfo(result.table);
    this.format = format;
    this.length = length;
    this.columns = Object.freeze(columns);
    this.layer = result.layer;
    this.layers = Object.freeze(result.layers.slice());
    this.#bytes = result.table;
    this.#ids = result.ids;
  }

  /** The rows as a GeoJSON FeatureCollection, a new one per call: a GeoJSON source's `data`. */
  toGeoJSON(): DataFeatureCollection {
    const fc = tableToGeoJSON(this.#bytes);
    return this.#ids ? withIds(fc, this.#ids) : fc;
  }

  /** @internal The rows and ids as the data worker's `write` takes them (copies). */
  writeArgs(): { table: ArrayBuffer; ids: ArrayBuffer | null } {
    return { table: this.#bytes.slice(0), ids: this.#ids?.slice(0) ?? null };
  }

  /** A copy of the rows in @geom.Table's byte form (docs/FORMATS.md "Table"), which mbmap/analysis's `load` takes. */
  tableBytes(): ArrayBuffer {
    return this.#bytes.slice(0);
  }
}

const client = new WorkerClient("data");

function start(options: DataOptions): void {
  client.start(options.workerUrl ?? new URL("./data-worker.js", import.meta.url), (page) => ({
    wasm: wasmUrl(options.wasmUrl ?? new URL("./data.wasm", import.meta.url), page),
    proj: wasmUrl(options.projWasmUrl ?? new URL("./proj.wasm", import.meta.url), page),
    prj: new URL("./prjwkt.js", import.meta.url).href,
    xml: wasmUrl(options.xmlUrl ?? new URL("./xml.wasm", import.meta.url), page),
    geotiff: wasmUrl(options.geotiffUrl ?? new URL("./geotiff.wasm", import.meta.url), page),
  }));
}

const FORMATS: DataFormat[] = ["csv", "wkt", "wkb", "shapefile", "topojson", "kml", "gpx", "flatgeobuf", "geojson"];

function formatFor(options: ReadOptions, name: string | null): DataFormat {
  const format = options.format ?? (name === null ? null : formatOf(name));
  if (!FORMATS.includes(format as DataFormat)) {
    throw new Error(`mbmap: data: ${options.format === undefined ? "the format cannot be told from the input; give options.format" : `unknown format ${String(options.format)}`}`);
  }
  return format as DataFormat;
}

type Input = string | URL | Blob | ArrayBuffer | ArrayBufferView;

/** `input` as the data worker takes a source: `{ url, init }`, `{ blob }` or `{ bytes }` (copied, and added to `transfer`). */
function sourceOf(input: Input, options: ReadOptions, transfer: Transferable[]): object {
  if (typeof input === "string" || input instanceof URL) {
    const url = httpUrl(input, document.baseURI, "data: the URL");
    const r = options.transformRequest?.(url);
    const init = r ? { headers: r.headers, credentials: r.credentials } : undefined;
    return { url: r ? httpUrl(r.url, document.baseURI, "data: the URL") : url, init };
  }
  if (input instanceof Blob) return { blob: input };
  const bytes =
    input instanceof ArrayBuffer ? input.slice(0) :
    ArrayBuffer.isView(input) ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength).slice().buffer :
    null;
  if (!bytes) throw new Error("mbmap: data: read takes a URL, a Blob or bytes");
  transfer.push(bytes);
  return { bytes };
}

async function call(format: DataFormat, source: object, options: ReadOptions, transfer: Transferable[]): Promise<DataTable> {
  const { layer, encoding } = options;
  if (layer !== undefined && typeof layer !== "string") throw new Error("mbmap: data: invalid layer");
  if (encoding !== undefined && typeof encoding !== "string") throw new Error("mbmap: data: invalid encoding");
  if (options.crs !== undefined && (format === "kml" || format === "gpx" || format === "geojson")) throw new Error("mbmap: data: KML, GPX and GeoJSON are always in EPSG:4326; options.crs is for other formats");
  if (options.bbox !== undefined && format !== "flatgeobuf") throw new Error("mbmap: data: options.bbox is for FlatGeobuf");
  const bbox = options.bbox === undefined ? undefined : bboxArg(options.bbox);
  const crs = options.crs === undefined ? undefined : await crsArg(options.crs, "data");
  const args = { format, options: { ...(format === "csv" ? csvArgs(options) : {}), crs, layer, encoding, bbox }, ...source };
  start(options);
  return new DataTable(format, await client.call<ReadResult>("read", args, transfer));
}

/**
 * Reads `input`: an http(s) URL (fetched without credentials), a Blob or File, bytes (copied), a
 * shapefile's files picked together or its `{ shp, dbf, prj, cpg }` (npm/README.md has the rules).
 */
export async function read(input: Input | ArrayLike<File> | ShapefileParts<Input>, options: ReadOptions = {}): Promise<DataTable> {
  const transfer: Transferable[] = [];
  const files = Array.isArray(input) || (typeof FileList !== "undefined" && input instanceof FileList) ? Array.from(input as ArrayLike<File>) : null;
  if (files?.length === 1) return read(files[0], options);
  const parts = files ? shapefileParts(files) : (input as ShapefileParts<Input>)?.shp !== undefined ? (input as ShapefileParts<Input>) : null;
  if (files && !parts) throw new Error("mbmap: data: of several files, read takes a shapefile's (one .shp and its .dbf, .prj, .cpg)");
  if (parts) {
    const format = options.format ?? "shapefile";
    if (format !== "shapefile") throw new Error("mbmap: data: a shapefile's parts need format \"shapefile\"");
    const sources: Record<string, object> = {};
    for (const [k, v] of Object.entries(parts)) if (v !== undefined) sources[k] = sourceOf(v, options, transfer);
    return call(format, { parts: sources }, options, transfer);
  }
  const single = input as Input;
  const name = typeof single === "string" || single instanceof URL ? new URL(httpUrl(single, document.baseURI, "data: the URL")).pathname : single instanceof File ? single.name : null;
  return call(formatFor(options, name), sourceOf(single, options, transfer), options, transfer);
}

/** Reads `text` (CSV, WKT, hexadecimal WKB, TopoJSON, KML or GPX) as `options.format`. */
export async function parse(text: string, options: ReadOptions & { format: DataFormat }): Promise<DataTable> {
  if (typeof text !== "string") throw new Error("mbmap: data: parse takes a string");
  const bytes = new TextEncoder().encode(text).buffer;
  return call(formatFor(options, null), { bytes }, options, [bytes]);
}

/** `format` and, for CSV, how its rows are laid out. */
export interface WriteOptions extends DataOptions, CsvWriteOptions {
  format: WriteFormat;
}

/**
 * `input` (a DataTable, or a GeoJSON Feature or FeatureCollection) as `options.format`: GeoJSON as
 * `JSON.stringify` of `toGeoJSON()`, CSV as papaparse's `unparse`, KML as @placemarkio/tokml's
 * `toKML` write them (npm/README.md has the rules).
 */
export async function write(input: DataTable | object, options: WriteOptions): Promise<string> {
  const { format } = options ?? {};
  if (!["geojson", "csv", "kml"].includes(format)) throw new Error(`mbmap: data: unknown write format ${String(format)}`);
  if (!(input instanceof DataTable)) {
    if (!input || typeof input !== "object") throw new Error("mbmap: data: write takes a DataTable or a GeoJSON object");
    if (format === "geojson") return JSON.stringify(input);
    const { workerUrl, wasmUrl, projWasmUrl, xmlUrl, geotiffUrl } = options;
    input = await parse(JSON.stringify(input), { workerUrl, wasmUrl, projWasmUrl, xmlUrl, geotiffUrl, format: "geojson" });
  }
  const table = input as DataTable;
  if (format === "geojson") return JSON.stringify(table.toGeoJSON());
  const args = { format, options: format === "csv" ? csvWriteArgs(options) : {}, ...table.writeArgs() };
  start(options);
  const bytes = await client.call<ArrayBuffer>("write", args, [args.table, ...(args.ids ? [args.ids] : [])]);
  return new TextDecoder().decode(bytes);
}

/** A band of a raster, typed as geotiff's `readRasters` types it. */
export type RasterBand = Uint8Array | Int8Array | Uint16Array | Int16Array | Uint32Array | Int32Array | Float32Array | Float64Array;

/** Which pixels `readRaster` reads, as geotiff's `readRasters` takes them (`window`, `bbox`, `width`, `height`, `resX`,
 * `resY`, `resampleMethod`, `samples`, `fillValue`), `image` by index, `transformRequest` as `read`'s; npm/README.md has the rules. */
export interface RasterOptions extends DataOptions {
  window?: [number, number, number, number];
  bbox?: [number, number, number, number];
  width?: number;
  height?: number;
  resX?: number;
  resY?: number;
  resampleMethod?: "nearest" | "bilinear";
  image?: number;
  samples?: number[];
  fillValue?: number;
  transformRequest?: ReadOptions["transformRequest"];
}

/** Pixels `readRaster` read: `bands` per sample, the window's `bbox` and `resolution` (y negative north up; null
 * without geo tags) in `crs` (GeoKeys' EPSG code or null), `noData` (GDAL_NODATA or null); npm/README.md has the rest. */
export interface Raster {
  width: number;
  height: number;
  bands: RasterBand[];
  bbox: [number, number, number, number] | null;
  resolution: [number, number] | null;
  window: [number, number, number, number];
  image: number;
  images: number;
  crs: number | null;
  noData: number | null;
  pixelIsPoint: boolean;
}

const isFour = (v: unknown): boolean => Array.isArray(v) && v.length === 4 && v.every(Number.isFinite);

/**
 * Reads pixels of the GeoTIFF or COG `input` (an http(s) URL, read by range requests; a Blob, read
 * in slices; or bytes) as geotiff 3.0.5's `readRasters` does (npm/README.md has the rules).
 */
export async function readRaster(input: Input, options: RasterOptions = {}): Promise<Raster> {
  const { window: wnd, bbox, width, height, resX, resY, resampleMethod, image, samples, fillValue } = options;
  const fail = (what: string): never => {
    throw new Error(`mbmap: data: invalid ${what}`);
  };
  if (wnd !== undefined && (!isFour(wnd) || !wnd.every(Number.isInteger))) fail("window");
  if (bbox !== undefined && !isFour(bbox)) fail("bbox");
  for (const [what, n] of [["width", width], ["height", height], ["image", image]] as const) {
    if (n !== undefined && !(Number.isInteger(n) && n >= (what === "image" ? 0 : 1) && n <= 65536)) fail(what);
  }
  for (const [what, n] of [["resX", resX], ["resY", resY], ["fillValue", fillValue]] as const) if (n !== undefined && !Number.isFinite(n)) fail(what);
  if (resampleMethod !== undefined && !["nearest", "bilinear", "linear"].includes(resampleMethod)) fail("resampleMethod");
  if (samples !== undefined && (!Array.isArray(samples) || !samples.every((s) => Number.isInteger(s) && s >= 0))) fail("samples");
  const transfer: Transferable[] = [];
  const source = sourceOf(input, options, transfer);
  start(options);
  return client.call<Raster>("readRaster", { ...source, options: { window: wnd, bbox, width, height, resX, resY, resampleMethod, image, samples, fillValue } }, transfer);
}

/** What `rasterInfo` gives: `crs` (EPSG code), `bounds` in longitude and latitude, `maxzoom` (256-px tiles), `samples`, `noData`, `range` (band 0's values in the coarsest image). */
export interface RasterInfo {
  crs: number;
  bounds: [number, number, number, number];
  maxzoom: number;
  samples: number;
  noData: number | null;
  range: [number, number] | null;
}

/** How `rasterTile` draws (npm/README.md): `tileSize`, `bands`, `range`, `colors` (`[value, color]` stops), `dem`, `resampling`. */
export interface RasterTileOptions extends DataOptions {
  tileSize?: 256 | 512;
  bands?: number[];
  range?: [number, number];
  colors?: [number, string][];
  dem?: boolean;
  resampling?: "nearest" | "bilinear";
  transformRequest?: ReadOptions["transformRequest"];
}

/** What drawing the GeoTIFF (EPSG:3857 or 4326) of `input` needs. */
export async function rasterInfo(input: Input, options: DataOptions & { transformRequest?: ReadOptions["transformRequest"] } = {}): Promise<RasterInfo> {
  const transfer: Transferable[] = [];
  const source = sourceOf(input, options, transfer);
  start(options);
  return client.call<RasterInfo>("rasterInfo", source, transfer);
}

/** XYZ tile `z`/`x`/`y` of the GeoTIFF (EPSG:3857 or 4326) of `input` as a PNG, or null where it has no pixel. */
export async function rasterTile(input: Input, z: number, x: number, y: number, options: RasterTileOptions = {}): Promise<ArrayBuffer | null> {
  const { tileSize = 256, bands, range, colors, dem, resampling } = options;
  const fail = (what: string): never => {
    throw new Error(`mbmap: data: invalid ${what}`);
  };
  if (![z, x, y].every(Number.isInteger) || z < 0 || z > 24 || x < 0 || y < 0 || x >= 2 ** z || y >= 2 ** z) fail("tile");
  if (bands !== undefined && (!Array.isArray(bands) || bands.length < 1 || bands.length > 4 || !bands.every((b) => Number.isInteger(b) && b >= 0))) fail("bands");
  if (range !== undefined && !(Array.isArray(range) && range.length === 2 && range.every(Number.isFinite))) fail("range");
  if (colors !== undefined && !(Array.isArray(colors) && colors.every((c) => Array.isArray(c) && Number.isFinite(c[0]) && typeof c[1] === "string"))) fail("colors");
  if (resampling !== undefined && resampling !== "nearest" && resampling !== "bilinear") fail("resampling");
  const transfer: Transferable[] = [];
  const source = sourceOf(input, options, transfer);
  start(options);
  return client.call<ArrayBuffer | null>("rasterTile", { ...source, options: { z, x, y, tileSize, bands, range, colors, dem: dem === true, resampling } }, transfer);
}

/** Stops the data worker; pending calls reject. */
export function terminate(): void {
  client.terminate();
}

export { formatOf };
