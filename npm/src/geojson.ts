// GeoJSON sources, served by their own worker. `Map` imports this module only
// for styles that have one.
import { type ClusterQuery, clusterArgs, loadOptions, sameOptions } from "./geojson-options.ts";
import { httpUrl, workerScriptUrl, wasmUrl, type TransformedRequest } from "./urls.ts";

export type { ClusterQuery } from "./geojson-options.ts";

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
  cluster(source: string, query: ClusterQuery): Promise<unknown>;
  terminate(): void;
}

/**
 * Starts the GeoJSON worker and loads `sources`, resolving data URLs against `base` and asking `transform`
 * (the map's `transformRequest`, as `"Source"`) about them; `compile` turns a source's `clusterProperties`
 * into what the worker's module with expressions (`geojson-properties.wasm`) reads.
 */
export function createGeoJSONTiles(
  sources: GeoJSONSource[],
  base: URL,
  onError: (error: Error) => void,
  urls: { workerUrl?: string | URL; wasmUrl?: string | URL; propertiesWasmUrl?: string | URL } = {},
  compile: (clusterProperties: string) => Uint8Array = () => new Uint8Array(0),
  transform: (url: string) => TransformedRequest | undefined = () => undefined,
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
  worker.postMessage({
    type: "init",
    wasm: wasmUrl(urls.wasmUrl ?? new URL("./geojson.wasm", import.meta.url), page),
    propsWasm: wasmUrl(urls.propertiesWasmUrl ?? new URL("./geojson-properties.wasm", import.meta.url), page),
  });
  const load = (s: GeoJSONSource, n: number) => {
    const p = s.spec.cluster === true && s.spec.clusterProperties ? compile(JSON.stringify(s.spec.clusterProperties)) : null;
    const options = { type: "load", source: n, ...loadOptions(s.spec), ...(p && p.length > 0 ? { properties: p } : {}) };
    const data = s.spec.data;
    if (typeof data === "string") {
      const given = new URL(data, base).href;
      const r = transform(given);
      let url: string;
      try {
        url = httpUrl(r?.url ?? given, base, `GeoJSON source ${s.id}: data`);
      } catch (err) {
        onError(err as Error);
        return;
      }
      worker.postMessage({ ...options, url, init: r ? { headers: r.headers, credentials: r.credentials } : undefined });
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
        if (old && sameOptions(old.source.spec, s.spec)) continue;
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
