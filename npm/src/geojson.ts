// GeoJSON sources: a worker of their own reads the data and cuts tiles in
// wasm (geojson_worker). `Map` imports this module only when a style has a
// GeoJSON source, so other maps never load it.
import { workerScriptUrl, wasmUrl } from "./urls";

/** A GeoJSON source of the style, by id. */
export interface GeoJSONSource {
  id: string;
  /** The GeoJSON itself, or a URL to fetch it from (without credentials). */
  data: unknown;
  maxzoom: number;
  buffer: number;
  tolerance: number;
}

export interface GeoJSONTiles {
  /** A source's tile as an encoded columnar tile, or null where it has nothing. */
  tile(source: string, z: number, x: number, y: number): Promise<ArrayBuffer | null>;
  terminate(): void;
}

/**
 * Starts the GeoJSON worker and loads `sources` into it. `base` resolves
 * data URLs; `onError` hears of sources that cannot be loaded.
 */
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
  let next = 0;
  worker.onmessage = (e: MessageEvent) => {
    const msg = e.data;
    if (msg?.type === "tile") {
      pending.get(msg.id)?.(msg.bytes instanceof ArrayBuffer ? msg.bytes : null);
      pending.delete(msg.id);
    } else if (msg?.type === "error") {
      onError(new Error(`mbmap: GeoJSON source ${sources[msg.source]?.id}: ${msg.message}`));
    }
  };
  worker.postMessage({ type: "init", wasm: wasmUrl(urls.wasmUrl ?? new URL("./geojson.wasm", import.meta.url), page) });
  const ids = new Map<string, number>();
  sources.forEach((s, i) => {
    ids.set(s.id, i);
    const options = { type: "load", source: i, maxzoom: s.maxzoom, buffer: s.buffer, tolerance: s.tolerance };
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
  });
  return {
    tile(source, z, x, y) {
      const i = ids.get(source);
      if (i === undefined) return Promise.resolve(null);
      const id = next++;
      return new Promise((resolve) => {
        pending.set(id, resolve);
        worker.postMessage({ type: "tile", id, source: i, z, x, y });
      });
    },
    terminate() {
      worker.terminate();
      for (const resolve of pending.values()) resolve(null);
      pending.clear();
    },
  };
}
