// GeoJSON sources, served by their own worker. `Map` imports this module only
// for styles that have one.
import { type ClusterQuery, clusterArgs, loadOptions, sameOptions } from "./geojson-options.ts";
import { type GeoJSONSourceDiff, type Updateable, applySourceDiff, geometryBounds, isSourceDiff, mergeSourceDiffs, tileMeets, toUpdateable } from "./geojson-diff.ts";
import { httpUrl, workerScriptUrl, wasmUrl, type TransformedRequest } from "./urls.ts";
import { encodeDiff } from "../../geojson_worker/js/diff.mjs";

export type { ClusterQuery } from "./geojson-options.ts";
export type { GeoJSONSourceDiff } from "./geojson-diff.ts";

/** A GeoJSON source of the style: its id and its specification, whose `data` is the GeoJSON itself or a URL to fetch it from (without credentials). */
export interface GeoJSONSource {
  id: string;
  spec: Record<string, unknown>;
}

/**
 * `tile` gives a source's tile as an encoded columnar tile, or null where it has nothing. `set` loads `sources` in place of
 * the current ones (data compared by identity) and returns the ids of those it kept but loaded again, whose tiles are now
 * stale. `cluster` answers a cluster query as MapLibre's GeoJSONSource does (null if the source does not cluster).
 */
export interface GeoJSONTiles {
  tile(source: string, z: number, x: number, y: number): Promise<ArrayBuffer | null>;
  set(sources: GeoJSONSource[], base: URL): string[];
  /** MapLibre's `updateData`: applied once the source's earlier loads have finished (diffs meanwhile merged), settled when it has none left. */
  update(source: string, diff: GeoJSONSourceDiff): Promise<void>;
  cluster(source: string, query: ClusterQuery): Promise<unknown>;
  terminate(): void;
}

/** Whether a diff changed tile z/x/y (MapLibre's `shouldReloadTile`); null when it may have changed any (clusters, `removeAll`). */
export type Reload = ((z: number, x: number, y: number) => boolean) | null;

/** A source loaded: the number the worker knows it by, `busy` the load awaited (0 for none), `waiting` the diff after it. */
interface Loaded {
  n: number;
  source: GeoJSONSource;
  busy: number;
  waiting?: GeoJSONSourceDiff;
  settled: (() => void)[];
  updateable?: Updateable;
  fetched?: ArrayBuffer;
}

/** MapLibre's GeoJSON tiles are 512 px wide whatever the style says. */
const TILE_SIZE = 512;

/**
 * Starts the GeoJSON worker and loads `sources`, resolving data URLs against `base` and asking `transform`
 * (the map's `transformRequest`, as `"Source"`) about them; `compile` turns a source's `clusterProperties` into what
 * the worker's module with expressions (`geojson-properties.wasm`) reads; `updated` gets a diff's data and changed tiles.
 */
export function createGeoJSONTiles(
  sources: GeoJSONSource[],
  base: URL,
  onError: (error: Error) => void,
  urls: { workerUrl?: string | URL; wasmUrl?: string | URL; propertiesWasmUrl?: string | URL } = {},
  compile: (clusterProperties: string) => Uint8Array = () => new Uint8Array(0),
  transform: (url: string) => TransformedRequest | undefined = () => undefined,
  updated: (source: string, data: unknown, reload: Reload) => void = () => {},
): GeoJSONTiles {
  const page = new URL(document.baseURI);
  const worker = new Worker(
    workerScriptUrl(urls.workerUrl ?? new URL("./geojson-worker.js", import.meta.url), page, location.origin),
    { type: "module" },
  );
  const pending = new Map<number, (bytes: ArrayBuffer | null) => void>();
  const asked = new Map<number, [(result: unknown) => void, (error: Error) => void]>();
  const loaded = new Map<string, Loaded>();
  let nextLoad = 1;
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
    for (const l of loaded.values()) settle(l);
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
    } else if (msg?.type === "loaded" || msg?.type === "error") {
      const found = [...loaded].find(([, l]) => l.n === msg.source);
      if (msg.type === "error") onError(new Error(`mbmap: GeoJSON source ${found?.[0]}: ${msg.message}`));
      if (!found || msg.id !== found[1].busy) return;
      const [id, l] = found;
      if (msg.fetched instanceof ArrayBuffer) l.fetched = msg.fetched;
      l.busy = 0;
      if (l.waiting) send(id, l);
      else settle(l);
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
  worker.postMessage({
    type: "init",
    wasm: wasmUrl(urls.wasmUrl ?? new URL("./geojson.wasm", import.meta.url), page),
    propsWasm: wasmUrl(urls.propertiesWasmUrl ?? new URL("./geojson-properties.wasm", import.meta.url), page),
  });
  const settle = (l: Loaded) => {
    for (const resolve of l.settled.splice(0)) resolve();
  };
  // Posts `s`'s data; returns the load's number, 0 if it could not be asked.
  const load = (s: GeoJSONSource, n: number): number => {
    const p = s.spec.cluster === true && s.spec.clusterProperties ? compile(JSON.stringify(s.spec.clusterProperties)) : null;
    const id = nextLoad++;
    const options = { type: "load", source: n, id, ...loadOptions(s.spec), ...(p && p.length > 0 ? { properties: p } : {}) };
    const data = s.spec.data;
    if (typeof data === "string") {
      const given = new URL(data, base).href;
      const r = transform(given);
      let url: string;
      try {
        url = httpUrl(r?.url ?? given, base, `GeoJSON source ${s.id}: data`);
      } catch (err) {
        onError(err as Error);
        return 0;
      }
      worker.postMessage({ ...options, url, init: r ? { headers: r.headers, credentials: r.credentials } : undefined });
    } else {
      const bytes = new TextEncoder().encode(JSON.stringify(data)).buffer;
      worker.postMessage({ ...options, bytes }, [bytes]);
    }
    return id;
  };
  // The features diffs apply to, by id; undefined when they cannot (MapLibre's error). A URL that failed to load counts as no data, as in MapLibre's worker.
  const updateable = (l: Loaded, key: string | undefined): Updateable | undefined => {
    if (l.updateable) return l.updateable;
    const data = l.source.spec.data;
    if (typeof data !== "string") return toUpdateable(data, key);
    return toUpdateable(l.fetched ? JSON.parse(new TextDecoder().decode(l.fetched)) : null, key);
  };
  // Applies the diff waiting to the data kept here and sends it to the worker, which updates its index as geojson-vt does.
  const send = (id: string, l: Loaded) => {
    const diff = l.waiting!;
    l.waiting = undefined;
    const spec = l.source.spec;
    const key = typeof spec.promoteId === "string" ? spec.promoteId : undefined;
    try {
      const features = updateable(l, key);
      if (!features) throw new Error(`mbmap: GeoJSONSource "${id}": GeoJSON data is not compatible with updateData`);
      const affected = applySourceDiff(features, diff, key);
      const data = { type: "FeatureCollection", features: [...features.values()] };
      l.updateable = features;
      l.fetched = undefined;
      l.source = { id, spec: { ...spec, data } };
      const bytes = encodeDiff(diff).buffer as ArrayBuffer;
      l.busy = nextLoad++;
      worker.postMessage({ type: "update", source: l.n, id: l.busy, diff: bytes }, [bytes]);
      const all = diff.removeAll || spec.cluster === true;
      const buffer = loadOptions(spec).buffer / TILE_SIZE;
      const bounds = geometryBounds(affected);
      updated(id, data, all ? null : (z, x, y) => tileMeets(buffer, bounds, z, x, y));
    } catch (err) {
      onError(err as Error);
    }
    if (!l.busy) settle(l);
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
        settle(l);
      }
      for (const s of next) {
        const old = loaded.get(s.id);
        if (old && sameOptions(old.source.spec, s.spec)) {
          // Features are keyed by `promoteId`.
          if (old.source.spec.promoteId !== s.spec.promoteId) old.updateable = undefined;
          old.source = s;
          continue;
        }
        const n = old?.n ?? nextSource++;
        // New data drops the diffs waiting, as MapLibre's `setData` does; their promises settle after it.
        const l: Loaded = { n, source: s, busy: 0, settled: old?.settled ?? [] };
        loaded.set(s.id, l);
        l.busy = load(s, n);
        if (!l.busy) settle(l);
        if (old) reloaded.push(s.id);
      }
      return reloaded;
    },
    update(source, diff) {
      const l = loaded.get(source);
      if (!l) return Promise.reject(new Error(`mbmap: source "${source}" is not a GeoJSON source`));
      if (!isSourceDiff(diff)) return Promise.reject(new Error(`mbmap: GeoJSON source ${source}: not a GeoJSONSourceDiff`));
      if (stopped !== null) return Promise.reject(new Error(stopped));
      const key = typeof l.source.spec.promoteId === "string" ? l.source.spec.promoteId : undefined;
      const copy = JSON.parse(JSON.stringify(diff)) as GeoJSONSourceDiff;
      l.waiting = l.waiting ? mergeSourceDiffs(l.waiting, copy, key) : copy;
      const settled = new Promise<void>((resolve) => l.settled.push(resolve));
      if (!l.busy) send(source, l);
      return settled;
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
