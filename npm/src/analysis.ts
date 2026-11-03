// `mbmap/analysis`: spatial analysis in a worker of its own, started on the
// first `load`. Measures and predicates match Turf.js; the index is flatbush;
// geometry operations are Clipper2's, in a module loaded on their first use.
import { wasmUrl } from "./urls";
import { WorkerClient } from "./worker-client";

/** `[minX, minY, maxX, maxY]` in degrees. */
export type BBox = [number, number, number, number];

/**
 * Where the analysis worker and its wasm (`workerUrl`, `wasmUrl`), the geometry module
 * (`geometryWasmUrl`) and the coordinate system module (`projWasmUrl`) are served; by default
 * next to this module.
 */
export interface AnalysisOptions {
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
  geometryWasmUrl?: string | URL;
  projWasmUrl?: string | URL;
}

/**
 * A coordinate reference system: an EPSG code (`6677`, `"EPSG:6677"`, `"urn:ogc:def:crs:EPSG::6677"`),
 * `"CRS84"` (= 4326), a PROJ string, or a name given with `defineCrs`. EPSG codes known without a
 * definition are listed in the package README.
 */
export type Crs = string | number;

// An EPSG code, or a definition as docs/FORMATS.md "CRS definition" encodes it.
type CrsArg = number | Float64Array;

const named = new Map<string, string>();

/**
 * Names `projString` so that `name` can be passed wherever a CRS is taken, as
 * `proj4.defs` does (`defineCrs("EPSG:2154", "+proj=lcc ...")`); it overrides
 * a known EPSG code of that name. The string is parsed when first used.
 */
export function defineCrs(name: string, projString: string): void {
  if (typeof projString !== "string" || !projString.trim().startsWith("+")) throw new Error(`mbmap: analysis: not a PROJ string: ${String(projString)}`);
  named.set(name.trim().toUpperCase(), projString);
}

/** `crs` as the analysis worker takes it; PROJ strings load their parser on first use. */
async function crsArg(crs: Crs): Promise<CrsArg> {
  if (typeof crs === "number" && Number.isInteger(crs) && crs > 0) return crs;
  if (typeof crs === "string") {
    const key = crs.trim().toUpperCase();
    const text = named.get(key) ?? (key.startsWith("+") ? crs : undefined);
    if (text !== undefined) return (await import("./projstring.js")).parseProjString(text);
    if (/^(OGC:)?CRS84$/.test(key)) return 4326;
    const m = /^(?:EPSG:|URN:OGC:DEF:CRS:EPSG::)?(\d{1,6})$/.exec(key);
    if (m) return Number(m[1]);
  }
  throw new Error(`mbmap: analysis: not a CRS: ${String(crs)}`);
}

/**
 * How `buffer` measures its distance: `"geodesic"` on the ground (true meters
 * anywhere), `"planar"` in a projected CRS's plane (`crs`, Web Mercator by default).
 */
export type BufferMode = "geodesic" | "planar";

/**
 * `mode` (default `"geodesic"`); `join` and `cap` (default `"round"`); `arcTolerance`: how far round
 * edges may stray from true arcs in meters (default distance / 500); `crs`: the projected CRS a
 * planar buffer is measured in (default EPSG:3857).
 */
export interface BufferOptions {
  mode?: BufferMode;
  join?: "round" | "miter" | "square" | "bevel";
  cap?: "round" | "butt" | "square";
  arcTolerance?: number;
  crs?: Crs;
}

/** `crs`: the CRS of the data's coordinates (default EPSG:4326); they are kept as longitude and latitude. */
export interface LoadOptions extends AnalysisOptions {
  crs?: Crs;
}

/** Per polygon: the points inside, how many have a numeric value, their sum and mean (NaN without one). */
export interface Collected {
  count: Float64Array;
  numbers: Float64Array;
  sum: Float64Array;
  mean: Float64Array;
}

const client = new WorkerClient("analysis");

function start(options: AnalysisOptions): void {
  client.start(options.workerUrl ?? new URL("./analysis-worker.js", import.meta.url), (page) => ({
    wasm: wasmUrl(options.wasmUrl ?? new URL("./analysis.wasm", import.meta.url), page),
    geometry: wasmUrl(options.geometryWasmUrl ?? new URL("./geometry.wasm", import.meta.url), page),
    proj: wasmUrl(options.projWasmUrl ?? new URL("./proj.wasm", import.meta.url), page),
  }));
}

function call<T>(op: string, args: object, transfer: Transferable[] = []): Promise<T> {
  if (!client.started) return Promise.reject(new Error("mbmap: analysis: no dataset has been loaded"));
  return client.call<T>(op, args, transfer);
}

// Codes of geometry_worker/geometry.mbt.
const JOIN = { round: 0, miter: 1, square: 2, bevel: 3 } as const;
const CAP = { round: 0, butt: 1, square: 2 } as const;
const OVERLAY = { clip: 0, erase: 1, intersect: 2 } as const;

// Mirrors MEASURE_* in analysis_worker/datasets.mbt.
const MEASURE = { area: 0, length: 1, centroid: 2, bbox: 3 } as const;

/** GeoJSON read into the analysis worker, with its spatial index built on first use. */
export class Dataset {
  #id: number;
  #disposed = false;
  /** The number of features (a GeometryCollection counts once per member). */
  readonly length: number;

  /** @internal */
  constructor(id: number, length: number) {
    this.#id = id;
    this.length = length;
  }

  #call<T>(op: string, args: object = {}): Promise<T> {
    if (this.#disposed) return Promise.reject(new Error("mbmap: analysis: the dataset was disposed"));
    return call<T>(op, { dataset: this.#id, ...args });
  }

  static #idOf(d: Dataset, role: string): number {
    if (d.#disposed) throw new Error(`mbmap: analysis: the ${role} dataset was disposed`);
    return d.#id;
  }

  /** Each feature's area in square meters (0 for points and lines). */
  areas(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.area });
  }

  /** Each feature's length in meters, rings included (0 for points). */
  lengths(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.length });
  }

  /** Each feature's centroid as x, y pairs (the mean of its points, as Turf's `centroid`). */
  centroids(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.centroid });
  }

  /** Each feature's box as min x, min y, max x, max y. */
  bboxes(): Promise<Float64Array> {
    return this.#call("measure", { kind: MEASURE.bbox });
  }

  /** The features whose boxes meet `bbox`. */
  search(bbox: BBox): Promise<Int32Array> {
    return this.#call("search", { bbox });
  }

  /** Up to `k` features nearest to (x, y) by box distance in degrees, nearest first. */
  nearest(x: number, y: number, { k = 1, maxDistance = Infinity }: { k?: number; maxDistance?: number } = {}): Promise<Int32Array> {
    return this.#call("nearest", { x, y, k, maxDistance });
  }

  /** This dataset's point features with a point inside some polygon of `polygons` (boundaries count). */
  pointsWithin(polygons: Dataset): Promise<Int32Array> {
    return call("within", { points: Dataset.#idOf(this, "points"), polygons: Dataset.#idOf(polygons, "polygons") });
  }

  /** Per polygon of this dataset, the points of `points` inside it and their `property` values. */
  async collect(points: Dataset, property: string): Promise<Collected> {
    const v = await call<Float64Array>("collect", { polygons: Dataset.#idOf(this, "polygons"), points: Dataset.#idOf(points, "points"), property });
    const n = v.length / 3;
    const out = { count: new Float64Array(n), numbers: new Float64Array(n), sum: new Float64Array(n), mean: new Float64Array(n) };
    for (let i = 0; i < n; i++) {
      out.count[i] = v[i * 3];
      out.numbers[i] = v[i * 3 + 1];
      out.sum[i] = v[i * 3 + 2];
      out.mean[i] = out.numbers[i] > 0 ? out.sum[i] / out.numbers[i] : NaN;
    }
    return out;
  }

  /** Point counts of a `cols` x `rows` grid over `bbox`, row by row from its south edge. */
  grid(bbox: BBox, cols: number, rows: number): Promise<Int32Array> {
    return this.#call("grid", { bbox, cols, rows });
  }

  async #geometry(op: string, args: object): Promise<Dataset> {
    const { dataset, features } = await call<{ dataset: number; features: number }>(op, args);
    return new Dataset(dataset, features);
  }

  /**
   * Every feature grown by `meters` (shrunk if negative; lines and points only
   * grow) as polygons with its properties; vanished features keep their row
   * without geometry.
   */
  buffer(meters: number, { mode = "geodesic", join = "round", cap = "round", arcTolerance = 0, crs = 3857 }: BufferOptions = {}): Promise<Dataset> {
    if (!(mode in { geodesic: 0, planar: 1 }) || !(join in JOIN) || !(cap in CAP) || !Number.isFinite(meters) || !(arcTolerance >= 0)) {
      return Promise.reject(new Error("mbmap: analysis: invalid buffer options"));
    }
    return crsArg(crs).then((code) => this.#geometry("buffer", {
      dataset: Dataset.#idOf(this, "buffered"), meters, mode: mode === "planar" ? 1 : 0, join: JOIN[join], cap: CAP[cap], arcTolerance, crs: code,
    }));
  }

  /** All polygons merged into one feature without properties (lines and points are left out). */
  dissolve(): Promise<Dataset> {
    return this.#geometry("dissolve", { dataset: Dataset.#idOf(this, "dissolved") });
  }

  /** This dataset's features cut to the area of `other`'s polygons, with their properties. */
  clip(other: Dataset): Promise<Dataset> {
    return this.#geometry("overlay", { a: Dataset.#idOf(this, "clipped"), b: Dataset.#idOf(other, "clipping"), kind: OVERLAY.clip });
  }

  /** This dataset's features without the area of `other`'s polygons, with their properties. */
  erase(other: Dataset): Promise<Dataset> {
    return this.#geometry("overlay", { a: Dataset.#idOf(this, "erased"), b: Dataset.#idOf(other, "erasing"), kind: OVERLAY.erase });
  }

  /**
   * One feature per overlap of a feature here with a polygon of `other`, with
   * the properties of both (`other`'s keys also found here get the suffix `_2`).
   */
  intersect(other: Dataset): Promise<Dataset> {
    return this.#geometry("overlay", { a: Dataset.#idOf(this, "intersected"), b: Dataset.#idOf(other, "intersecting"), kind: OVERLAY.intersect });
  }

  /** The dataset as a GeoJSON FeatureCollection (feature ids are not kept), in `crs` if given. */
  async toGeoJSON({ crs }: { crs?: Crs } = {}): Promise<{ type: "FeatureCollection"; features: object[] }> {
    return this.#call("toGeoJSON", crs === undefined ? {} : { crs: await crsArg(crs) });
  }

  /** Frees the dataset in the worker; later calls on it reject. */
  dispose(): void {
    if (this.#disposed) return;
    this.#disposed = true;
    call("dispose", { dataset: this.#id }).catch(() => {});
  }
}

/** How a DEM's RGB holds elevations: MapLibre's encodings, GSI's, or custom factors. */
export type DemEncoding = "mapbox" | "terrarium" | "gsi" | { redFactor: number; greenFactor: number; blueFactor: number; baseShift?: number };

/** `zoom`: the tile zoom to read (the grid's cells are its pixels); `bounds`: the area to cover (the grid snaps outward to whole tiles). */
export interface DemOptions extends AnalysisOptions {
  zoom: number;
  bounds: BBox;
  encoding?: DemEncoding;
}

// Mirrors `load_dem`'s encodings in analysis_worker/dem.mbt.
function encodingArgs(e: DemEncoding = "mapbox"): number[] {
  if (e === "mapbox") return [0, 0, 0, 0, 0];
  if (e === "terrarium") return [1, 0, 0, 0, 0];
  if (e === "gsi") return [2, 0, 0, 0, 0];
  return [3, e.redFactor, e.greenFactor, e.blueFactor, e.baseShift ?? 0];
}

/** An elevation grid in the analysis worker, row by row from the north. */
export class DemGrid {
  #id: number;
  #disposed = false;
  readonly width: number;
  readonly height: number;
  /** `[west, south, east, north]` of the whole tiles it covers. */
  readonly bounds: BBox;

  /** @internal */
  constructor(id: number, width: number, height: number, bounds: BBox) {
    this.#id = id;
    this.width = width;
    this.height = height;
    this.bounds = bounds;
  }

  #call<T>(op: string, args: object = {}): Promise<T> {
    if (this.#disposed) return Promise.reject(new Error("mbmap: analysis: the grid was disposed"));
    return call<T>(op, { grid: this.#id, ...args });
  }

  /** Elevations in meters; NaN where the DEM has no data. */
  elevations(): Promise<Float64Array> {
    return this.#call("gridValues", { kind: 0 });
  }

  /** Slopes in degrees (gdaldem's Horn method). */
  slope(): Promise<Float64Array> {
    return this.#call("gridValues", { kind: 1 });
  }

  /** Aspects in degrees clockwise from north, facing downhill; NaN where flat. */
  aspect(): Promise<Float64Array> {
    return this.#call("gridValues", { kind: 2 });
  }

  /** Shades from 1 to 255 under light from `azimuth` degrees at `altitude` degrees (gdaldem's hillshade). */
  hillshade({ azimuth = 315, altitude = 45, zFactor = 1 }: { azimuth?: number; altitude?: number; zFactor?: number } = {}): Promise<Uint8Array> {
    return this.#call("gridHillshade", { azimuth, altitude, zFactor });
  }

  dispose(): void {
    if (this.#disposed) return;
    this.#disposed = true;
    call("dispose", { dataset: this.#id }).catch(() => {});
  }
}

/** Mosaics the DEM tiles of `tiles` (a `{z}/{x}/{y}` http(s) template) covering `bounds` into a grid. */
export async function loadDem(tiles: string, options: DemOptions): Promise<DemGrid> {
  start(options);
  const url = new URL(tiles, document.baseURI);
  if (!/^https?:$/.test(url.protocol)) throw new Error(`mbmap: analysis: DEM tiles must be an http(s) URL: ${url.href}`);
  // new URL() percent-encodes the placeholders' braces.
  const template = url.href.replace(/%7B([zxy])%7D/g, "{$1}");
  const r = await call<{ grid: number; width: number; height: number; bounds: BBox }>("loadDem", {
    url: template, z: options.zoom, bounds: options.bounds, encoding: encodingArgs(options.encoding),
  });
  return new DemGrid(r.grid, r.width, r.height, r.bounds);
}

/**
 * Reads GeoJSON into the analysis worker: an object, its UTF-8 bytes, or an
 * http(s) URL (resolved against the page, fetched without credentials).
 */
export async function load(data: unknown, options: LoadOptions = {}): Promise<Dataset> {
  const crs = options.crs === undefined ? undefined : await crsArg(options.crs);
  start(options);
  let args: object;
  let transfer: Transferable[] = [];
  if (typeof data === "string") {
    const url = new URL(data, document.baseURI);
    if (!/^https?:$/.test(url.protocol)) throw new Error(`mbmap: analysis: data must be an http(s) URL: ${url.href}`);
    args = { url: url.href };
  } else {
    // Copied, so the caller's buffer stays usable after the transfer.
    const bytes =
      data instanceof ArrayBuffer ? data.slice(0) :
      ArrayBuffer.isView(data) ? new Uint8Array(data.buffer, data.byteOffset, data.byteLength).slice().buffer :
      new TextEncoder().encode(JSON.stringify(data)).buffer;
    args = { bytes };
    transfer = [bytes];
  }
  const { dataset, features } = await call<{ dataset: number; features: number }>("load", { ...args, crs }, transfer);
  return new Dataset(dataset, features);
}

/**
 * x, y pairs taken from `from` to `to` (NaN where a projection cannot reach),
 * in the analysis worker; the first call loads the geometry module.
 */
export async function transform(coords: ArrayLike<number>, from: Crs, to: Crs, options: AnalysisOptions = {}): Promise<Float64Array> {
  const codes = { from: await crsArg(from), to: await crsArg(to) };
  start(options);
  const buffer = Float64Array.from(coords).buffer;
  if (buffer.byteLength % 16 !== 0) throw new Error("mbmap: analysis: coordinates must come in x, y pairs");
  return call<Float64Array>("transform", { coords: buffer, ...codes }, [buffer]);
}

/** Great-circle distance in meters between two `[lng, lat]` points; mirrors `@analysis.distance`. */
export function distance(from: [number, number], to: [number, number]): number {
  const rad = (d: number) => ((d % 360) * Math.PI) / 180;
  const sLat = Math.sin(rad(to[1] - from[1]) / 2);
  const sLng = Math.sin(rad(to[0] - from[0]) / 2);
  const a = sLat * sLat + sLng * sLng * Math.cos(rad(from[1])) * Math.cos(rad(to[1]));
  return 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 6371008.8;
}

/** Stops the analysis worker; datasets are lost and pending calls reject. */
export function terminate(): void {
  client.terminate();
}
