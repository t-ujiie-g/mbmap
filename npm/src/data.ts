// `mbmap/data`: CSV, WKT, WKB, KML/KMZ and GPX read in a worker of its own, started
// on the first call (KML and GPX by a second wasm), into tables that are both a
// GeoJSON source's data (`toGeoJSON`) and an mbmap/analysis dataset (`load(table)`).
import { tableInfo, tableToGeoJSON } from "../../wasmio/js/table.mjs";
import { csvArgs, formatOf, type CsvOptions, type DataFormat } from "./data-format";
import { httpUrl, wasmUrl } from "./urls";
import { WorkerClient } from "./worker-client";

export type { CsvOptions, DataFormat };

/** What `DataTable.toGeoJSON` gives: a feature per row, its geometry null without one. */
export interface DataFeatureCollection {
  type: "FeatureCollection";
  features: { type: "Feature"; geometry: { type: string; coordinates: unknown } | null; properties: Record<string, unknown> }[];
}

/**
 * Where the data worker (`workerUrl`), its wasm (`wasmUrl`) and the KML/GPX wasm it loads on the
 * first such read (`xmlUrl`) are served; by default next to this module.
 */
export interface DataOptions {
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
  xmlUrl?: string | URL;
}

/**
 * `format`: the reader (by default from a URL's or a File's name, see `formatOf`); `transformRequest`:
 * may change a URL's request as the map's does (no credentials are sent otherwise).
 */
export interface ReadOptions extends DataOptions, CsvOptions {
  format?: DataFormat;
  transformRequest?: (url: string) => { url: string; headers?: Record<string, string>; credentials?: RequestCredentials } | undefined;
}

/**
 * Rows read by `read` or `parse`: `length` rows (a geometry collection makes one per member),
 * `columns` the property keys. A row's geometry is null where it had none, or none valid.
 */
export class DataTable {
  readonly format: DataFormat;
  readonly length: number;
  readonly columns: readonly string[];
  #bytes: ArrayBuffer;

  /** @internal */
  constructor(format: DataFormat, bytes: ArrayBuffer) {
    const { length, columns } = tableInfo(bytes);
    this.format = format;
    this.length = length;
    this.columns = Object.freeze(columns);
    this.#bytes = bytes;
  }

  /** The rows as a GeoJSON FeatureCollection, a new one per call: a GeoJSON source's `data`. */
  toGeoJSON(): DataFeatureCollection {
    return tableToGeoJSON(this.#bytes);
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
    xml: wasmUrl(options.xmlUrl ?? new URL("./xml.wasm", import.meta.url), page),
  }));
}

function formatFor(options: ReadOptions, name: string | null): DataFormat {
  const format = options.format ?? (name === null ? null : formatOf(name));
  if (!["csv", "wkt", "wkb", "kml", "gpx"].includes(format as string)) {
    throw new Error(`mbmap: data: ${options.format === undefined ? "the format cannot be told from the input; give options.format" : `unknown format ${String(options.format)}`}`);
  }
  return format as DataFormat;
}

async function call(format: DataFormat, source: object, options: ReadOptions, transfer: Transferable[] = []): Promise<DataTable> {
  const args = { format, options: format === "csv" ? csvArgs(options) : {}, ...source };
  start(options);
  return new DataTable(format, await client.call<ArrayBuffer>("read", args, transfer));
}

/**
 * Reads `input`: an http(s) URL (resolved against the page, fetched without credentials), a Blob or
 * File, or bytes (copied). A string is always a URL; text goes to `parse`.
 */
export async function read(input: string | URL | Blob | ArrayBuffer | ArrayBufferView, options: ReadOptions = {}): Promise<DataTable> {
  if (typeof input === "string" || input instanceof URL) {
    const url = httpUrl(input, document.baseURI, "data: the URL");
    const r = options.transformRequest?.(url);
    const init = r ? { headers: r.headers, credentials: r.credentials } : undefined;
    const href = r ? httpUrl(r.url, document.baseURI, "data: the URL") : url;
    return call(formatFor(options, new URL(url).pathname), { url: href, init }, options);
  }
  if (input instanceof Blob) {
    return call(formatFor(options, input instanceof File ? input.name : null), { blob: input }, options);
  }
  const bytes =
    input instanceof ArrayBuffer ? input.slice(0) :
    ArrayBuffer.isView(input) ? new Uint8Array(input.buffer, input.byteOffset, input.byteLength).slice().buffer :
    null;
  if (!bytes) throw new Error("mbmap: data: read takes a URL, a Blob or bytes");
  return call(formatFor(options, null), { bytes }, options, [bytes]);
}

/** Reads `text` (CSV, WKT, hexadecimal WKB, KML or GPX) as `options.format`. */
export async function parse(text: string, options: ReadOptions & { format: DataFormat }): Promise<DataTable> {
  if (typeof text !== "string") throw new Error("mbmap: data: parse takes a string");
  const bytes = new TextEncoder().encode(text).buffer;
  return call(formatFor(options, null), { bytes }, options, [bytes]);
}

/** Stops the data worker; pending calls reject. */
export function terminate(): void {
  client.terminate();
}

export { formatOf };
