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

/**
 * Where the data worker (`workerUrl`), its wasm (`wasmUrl`), the coordinate system module
 * (`projWasmUrl`, loaded for data in another CRS) and the KML/GPX wasm (`xmlUrl`, loaded on the
 * first such read) are served; by default next to this module.
 */
export interface DataOptions {
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
  projWasmUrl?: string | URL;
  xmlUrl?: string | URL;
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
    const { workerUrl, wasmUrl, projWasmUrl, xmlUrl } = options;
    input = await parse(JSON.stringify(input), { workerUrl, wasmUrl, projWasmUrl, xmlUrl, format: "geojson" });
  }
  const table = input as DataTable;
  if (format === "geojson") return JSON.stringify(table.toGeoJSON());
  const args = { format, options: format === "csv" ? csvWriteArgs(options) : {}, ...table.writeArgs() };
  start(options);
  const bytes = await client.call<ArrayBuffer>("write", args, [args.table, ...(args.ids ? [args.ids] : [])]);
  return new TextDecoder().decode(bytes);
}

/** Stops the data worker; pending calls reject. */
export function terminate(): void {
  client.terminate();
}

export { formatOf };
