// GeoJSON sources, served by their own worker. `Map` imports this module only
// for styles that have one.
import { workerScriptUrl, wasmUrl } from "./urls";

/** A GeoJSON source of the style: its id and its specification, whose `data` is the GeoJSON itself or a URL to fetch it from (without credentials). */
export interface GeoJSONSource {
  id: string;
  spec: Record<string, unknown>;
}

/** A cluster query: the expansion zoom, the children or the leaves (`limit`, `offset`) of cluster `cluster`. */
export type ClusterQuery =
  | { op: "expansion" | "children"; cluster: number }
  | { op: "leaves"; cluster: number; limit?: number; offset?: number };

/**
 * `tile` gives a source's tile as an encoded columnar tile, or null where it has nothing. `set` loads `sources` in place of
 * the current ones (data compared by identity) and returns the ids of those it kept but loaded again, whose tiles are now
 * stale. `cluster` answers a cluster query as MapLibre's GeoJSONSource does (null if the source does not cluster).
 */
export interface GeoJSONTiles {
  tile(source: string, z: number, x: number, y: number): Promise<ArrayBuffer | null>;
  set(sources: GeoJSONSource[], base: URL): string[];
  cluster(source: string, query: ClusterQuery): Promise<unknown>;
  terminate(): void;
}

const INT32_MAX = 2 ** 31 - 1;

/** The options the worker loads a source with, derived as MapLibre's GeoJSONSource does (`clusterMaxZoom` 0 or unset means `maxzoom` - 1). */
function loadOptions(spec: Record<string, unknown>) {
  const num = (v: unknown, d: number) => (typeof v === "number" ? v : d);
  const maxzoom = num(spec.maxzoom, 18);
  const clusterMaxZoom = num(spec.clusterMaxZoom, 0);
  const cluster =
    spec.cluster === true
      ? {
          maxZoom: Math.max(-1, Math.min(30, clusterMaxZoom ? Math.round(clusterMaxZoom) : maxzoom - 1)),
          radius: num(spec.clusterRadius, 0) || 50,
          minPoints: Math.min(INT32_MAX, Math.ceil(Math.max(2, num(spec.clusterMinPoints, 0) || 2))),
        }
      : null;
  return { maxzoom, buffer: num(spec.buffer, 128), tolerance: num(spec.tolerance, 0.375), lineMetrics: spec.lineMetrics === true, cluster };
}

function sameOptions(a: GeoJSONSource, b: GeoJSONSource): boolean {
  return a.spec.data === b.spec.data && JSON.stringify(loadOptions(a.spec)) === JSON.stringify(loadOptions(b.spec));
}

/**
 * `query` as the worker takes it: integer ids, a `limit` of 0 (MapLibre's 10), more or
 * Infinity (-1), an `offset` from 0. Throws on anything else.
 */
function clusterArgs(query: ClusterQuery) {
  const { cluster } = query;
  if (!Number.isInteger(cluster) || Math.abs(cluster) > INT32_MAX) throw new Error(`mbmap: no cluster with the id ${cluster}`);
  if (query.op !== "leaves") return query;
  const limit = query.limit ?? 10;
  const offset = query.offset ?? 0;
  if (!(limit === Infinity || (Number.isInteger(limit) && limit >= 0))) throw new Error(`mbmap: bad limit ${limit}`);
  if (!(Number.isInteger(offset) && offset >= 0)) throw new Error(`mbmap: bad offset ${offset}`);
  return { op: "leaves", cluster, limit: limit > INT32_MAX ? -1 : limit, offset: Math.min(offset, INT32_MAX) };
}

/** Starts the GeoJSON worker and loads `sources`, resolving data URLs against `base`. */
export function createGeoJSONTiles(
  sources: GeoJSONSource[],
  base: URL,
  onError: (error: Error) => void,
  urls: { workerUrl?: string | URL; wasmUrl?: string | URL } = {},
): GeoJSONTiles {
  const page = new URL(document.baseURI);
  const worker = new Worker(
    workerScriptUrl(urls.workerUrl ?? new URL("./geojson-worker.js", import.meta.url), page, location.origin),
    { type: "module" },
  );
  const pending = new Map<number, (bytes: ArrayBuffer | null) => void>();
  const asked = new Map<number, [(result: unknown) => void, (error: Error) => void]>();
  // Each source loaded, by id, under the number the worker knows it by.
  const loaded = new Map<string, { n: number; source: GeoJSONSource }>();
  let nextTile = 0;
  let nextQuery = 0;
  let nextSource = 0;
  // Why the worker stopped (null while it runs): tiles asked from then on are empty, cluster queries refused.
  let stopped: string | null = null;
  const stop = (why: string): string => {
    const message = (stopped ??= `mbmap: ${why}`);
    worker.terminate();
    for (const resolve of pending.values()) resolve(null);
    pending.clear();
    for (const [, reject] of asked.values()) reject(new Error(message));
    asked.clear();
    return message;
  };
  worker.onmessage = (e: MessageEvent) => {
    const msg = e.data;
    if (msg?.type === "tile") {
      pending.get(msg.id)?.(msg.bytes instanceof ArrayBuffer ? msg.bytes : null);
      pending.delete(msg.id);
    } else if (msg?.type === "cluster") {
      const [resolve, reject] = asked.get(msg.id) ?? [];
      asked.delete(msg.id);
      if (typeof msg.error === "string") reject?.(new Error(`mbmap: ${msg.error}`));
      else resolve?.(msg.result);
    } else if (msg?.type === "error") {
      const id = [...loaded].find(([, l]) => l.n === msg.source)?.[0];
      onError(new Error(`mbmap: GeoJSON source ${id}: ${msg.message}`));
    }
  };
  // A worker that fails to load or run fails what it was asked rather than leaving it waiting.
  const fail = (why: string) => {
    if (stopped !== null) return;
    onError(new Error(stop(`GeoJSON: ${why}`)));
  };
  worker.onerror = (e: ErrorEvent) => {
    e.preventDefault();
    fail(e.message || "the worker failed");
  };
  worker.onmessageerror = () => fail("a message could not be read");
  worker.postMessage({ type: "init", wasm: wasmUrl(urls.wasmUrl ?? new URL("./geojson.wasm", import.meta.url), page) });
  const load = (s: GeoJSONSource, n: number) => {
    const options = { type: "load", source: n, ...loadOptions(s.spec) };
    const data = s.spec.data;
    if (typeof data === "string") {
      const url = new URL(data, base);
      if (!/^https?:$/.test(url.protocol)) {
        onError(new Error(`mbmap: GeoJSON source ${s.id}: data must be an http(s) URL: ${url.href}`));
        return;
      }
      worker.postMessage({ ...options, url: url.href });
    } else {
      const bytes = new TextEncoder().encode(JSON.stringify(data)).buffer;
      worker.postMessage({ ...options, bytes }, [bytes]);
    }
  };
  const tiles: GeoJSONTiles = {
    tile(source, z, x, y) {
      const l = loaded.get(source);
      if (l === undefined || stopped !== null) return Promise.resolve(null);
      const id = nextTile++;
      return new Promise((resolve) => {
        pending.set(id, resolve);
        worker.postMessage({ type: "tile", id, source: l.n, z, x, y });
      });
    },
    set(next, nextBase) {
      base = nextBase;
      const reloaded: string[] = [];
      const ids = new Set(next.map((s) => s.id));
      for (const [id, l] of loaded) {
        if (ids.has(id)) continue;
        worker.postMessage({ type: "unload", source: l.n });
        loaded.delete(id);
      }
      for (const s of next) {
        const old = loaded.get(s.id);
        if (old && sameOptions(old.source, s)) continue;
        const n = old?.n ?? nextSource++;
        loaded.set(s.id, { n, source: s });
        load(s, n);
        if (old) reloaded.push(s.id);
      }
      return reloaded;
    },
    cluster(source, query) {
      return new Promise((resolve, reject) => {
        const l = loaded.get(source);
        if (l === undefined) throw new Error(`mbmap: source "${source}" is not a GeoJSON source`);
        if (stopped !== null) throw new Error(stopped);
        const id = nextQuery++;
        worker.postMessage({ type: "cluster", id, source: l.n, ...clusterArgs(query) });
        asked.set(id, [resolve, reject]);
      });
    },
    terminate() {
      stop("the map was removed");
    },
  };
  tiles.set(sources, base);
  return tiles;
}
