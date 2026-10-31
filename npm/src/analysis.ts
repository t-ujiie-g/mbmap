// `mbmap/analysis`: spatial analysis in a worker of its own, started on the
// first `load`. Measures and predicates match Turf.js; the index is flatbush.
import { wasmUrl, workerScriptUrl } from "./urls";

/** `[minX, minY, maxX, maxY]` in degrees. */
export type BBox = [number, number, number, number];

export interface AnalysisOptions {
  /** Where the analysis worker and its wasm are served (by default next to this module). */
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
}

/** Per polygon: the points inside, how many have a numeric value, their sum and mean (NaN without one). */
export interface Collected {
  count: Float64Array;
  numbers: Float64Array;
  sum: Float64Array;
  mean: Float64Array;
}

let worker: Worker | null = null;
const pending = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>();
let nextCall = 0;

function start(options: AnalysisOptions): Worker {
  if (worker) return worker;
  const page = new URL(document.baseURI);
  const w = new Worker(
    workerScriptUrl(options.workerUrl ?? new URL("./analysis-worker.js", import.meta.url), page, location.origin),
    { type: "module" },
  );
  w.onmessage = (e: MessageEvent) => {
    const msg = e.data;
    const call = msg?.type === "result" ? pending.get(msg.id) : undefined;
    if (!call) return;
    pending.delete(msg.id);
    if (typeof msg.error === "string") call.reject(new Error(`mbmap: analysis: ${msg.error}`));
    else call.resolve(msg.value);
  };
  w.postMessage({ type: "init", wasm: wasmUrl(options.wasmUrl ?? new URL("./analysis.wasm", import.meta.url), page) });
  worker = w;
  return w;
}

function call<T>(op: string, args: object, transfer: Transferable[] = []): Promise<T> {
  if (!worker) return Promise.reject(new Error("mbmap: analysis: no dataset has been loaded"));
  const id = nextCall++;
  const w = worker;
  return new Promise<T>((resolve, reject) => {
    pending.set(id, { resolve, reject });
    w.postMessage({ type: "call", id, op, ...args }, transfer);
  });
}

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

  /** @internal */
  idFor(other: string): number {
    if (this.#disposed) throw new Error(`mbmap: analysis: the ${other} dataset was disposed`);
    return this.#id;
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
    return call("within", { points: this.idFor("points"), polygons: polygons.idFor("polygons") });
  }

  /** Per polygon of this dataset, the points of `points` inside it and their `property` values. */
  async collect(points: Dataset, property: string): Promise<Collected> {
    const v = await call<Float64Array>("collect", { polygons: this.idFor("polygons"), points: points.idFor("points"), property });
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

  /** Frees the dataset in the worker; later calls on it reject. */
  dispose(): void {
    if (this.#disposed) return;
    this.#disposed = true;
    call("dispose", { dataset: this.#id }).catch(() => {});
  }
}

/**
 * Reads GeoJSON into the analysis worker: an object, its UTF-8 bytes, or an
 * http(s) URL (resolved against the page, fetched without credentials).
 */
export async function load(data: unknown, options: AnalysisOptions = {}): Promise<Dataset> {
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
  const { dataset, features } = await call<{ dataset: number; features: number }>("load", args, transfer);
  return new Dataset(dataset, features);
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
  worker?.terminate();
  worker = null;
  for (const p of pending.values()) p.reject(new Error("mbmap: analysis: terminated"));
  pending.clear();
}
