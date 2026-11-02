// GeoJSON sources, served by their own worker. `Map` imports this module only
// for styles that have one.
import { workerScriptUrl, wasmUrl } from "./urls";

/** A GeoJSON source of the style, by id: `data` is the GeoJSON itself, or a URL to fetch it from (without credentials). */
export interface GeoJSONSource {
  id: string;
  data: unknown;
  maxzoom: number;
  buffer: number;
  tolerance: number;
}

/**
 * `tile` gives a source's tile as an encoded columnar tile, or null where it has nothing.
 * `set` loads `sources` in place of the current ones (data compared by identity) and
 * returns the ids of the sources it kept but loaded again, whose tiles are now stale.
 */
export interface GeoJSONTiles {
  tile(source: string, z: number, x: number, y: number): Promise<ArrayBuffer | null>;
  set(sources: GeoJSONSource[], base: URL): string[];
  terminate(): void;
}

function sameOptions(a: GeoJSONSource, b: GeoJSONSource): boolean {
  return a.data === b.data && a.maxzoom === b.maxzoom && a.buffer === b.buffer && a.tolerance === b.tolerance;
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
  // Each source loaded, by id, under the number the worker knows it by.
  const loaded = new Map<string, { n: number; source: GeoJSONSource }>();
  let nextTile = 0;
  let nextSource = 0;
  worker.onmessage = (e: MessageEvent) => {
    const msg = e.data;
    if (msg?.type === "tile") {
      pending.get(msg.id)?.(msg.bytes instanceof ArrayBuffer ? msg.bytes : null);
      pending.delete(msg.id);
    } else if (msg?.type === "error") {
      const id = [...loaded].find(([, l]) => l.n === msg.source)?.[0];
      onError(new Error(`mbmap: GeoJSON source ${id}: ${msg.message}`));
    }
  };
  worker.postMessage({ type: "init", wasm: wasmUrl(urls.wasmUrl ?? new URL("./geojson.wasm", import.meta.url), page) });
  const load = (s: GeoJSONSource, n: number) => {
    const options = { type: "load", source: n, maxzoom: s.maxzoom, buffer: s.buffer, tolerance: s.tolerance };
    if (typeof s.data === "string") {
      const url = new URL(s.data, base);
      if (!/^https?:$/.test(url.protocol)) {
        onError(new Error(`mbmap: GeoJSON source ${s.id}: data must be an http(s) URL: ${url.href}`));
        return;
      }
      worker.postMessage({ ...options, url: url.href });
    } else {
      const bytes = new TextEncoder().encode(JSON.stringify(s.data)).buffer;
      worker.postMessage({ ...options, bytes }, [bytes]);
    }
  };
  const tiles: GeoJSONTiles = {
    tile(source, z, x, y) {
      const l = loaded.get(source);
      if (l === undefined) return Promise.resolve(null);
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
    terminate() {
      worker.terminate();
      for (const resolve of pending.values()) resolve(null);
      pending.clear();
    },
  };
  tiles.set(sources, base);
  return tiles;
}
