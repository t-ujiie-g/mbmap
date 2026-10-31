import * as engine from "mbmap-engine";
import type { GeoJSONSource, GeoJSONTiles } from "./geojson";
import { resolveTemplate, wasmUrl, workerScriptUrl } from "./urls";

/** `[lng, lat]` or `{ lng, lat }`, as in MapLibre. */
export type LngLatLike = [number, number] | { lng: number; lat: number };

export interface LngLat {
  lng: number;
  lat: number;
}

/**
 * A MapLibre style document. mbmap draws its background, fill and line
 * layers from one vector source; anything it cannot draw faithfully is an
 * error rather than being ignored.
 */
export interface StyleSpecification {
  version: 8;
  sources: Record<string, unknown>;
  layers: unknown[];
  [key: string]: unknown;
}

export interface MapOptions {
  /** The element (or its id) the map fills. It needs a size of its own. */
  container: HTMLElement | string;
  /** A style object, or the URL of one (fetched without credentials). */
  style: StyleSpecification | string;
  center?: LngLatLike;
  zoom?: number;
  /** Degrees clockwise from north that point up (default 0). */
  bearing?: number;
  /** Degrees of tilt from looking straight down, 0 to 60 (default 0). */
  pitch?: number;
  /** Tile workers; 0 (the default) picks half the hardware threads, 1 to 4. */
  workerCount?: number;
  /**
   * Where the worker script and its wasm are served. They default to the
   * files next to this module, which suits bundlers that understand
   * `new URL(..., import.meta.url)` and plain ESM serving. The worker must
   * be a same-origin http(s) URL and the wasm an http(s) one.
   */
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
  /** Like `workerUrl` and `wasmUrl`, for the worker of GeoJSON sources. */
  geojsonWorkerUrl?: string | URL;
  geojsonWasmUrl?: string | URL;
  /** Shows the sources' `attribution` text in a corner (default true). */
  attributionControl?: boolean;
}

export type MapEventType = "load" | "move" | "idle" | "error";

/**
 * `load` fires once, when the first view is drawn; `idle` each time the map
 * settles; `move` on every camera change; `error` when a style URL cannot be
 * used.
 */
export interface MapEvent {
  type: MapEventType;
  target: Map;
  error?: Error;
}

export type MapEventListener = (event: MapEvent) => void;

interface Camera {
  lng: number;
  lat: number;
  zoom: number;
  bearing: number;
  pitch: number;
}

function toLngLat(c: LngLatLike): LngLat {
  return Array.isArray(c) ? { lng: c[0], lat: c[1] } : { lng: c.lng, lat: c.lat };
}

function checkCamera(c: Camera): Camera {
  if (![c.lng, c.lat, c.zoom, c.bearing, c.pitch].every(Number.isFinite)) {
    throw new TypeError(`mbmap: center, zoom, bearing and pitch must be finite numbers: ${JSON.stringify(c)}`);
  }
  return c;
}

/** The style with tile URLs resolved against the style's own URL. */
function resolveTiles(style: StyleSpecification, base: URL): StyleSpecification {
  const sources = Object.fromEntries(
    Object.entries(style.sources ?? {}).map(([id, s]) => {
      const tiles = (s as { tiles?: unknown })?.tiles;
      if (!Array.isArray(tiles)) return [id, s];
      return [id, { ...(s as object), tiles: tiles.map((t) => (typeof t === "string" ? resolveTemplate(t, base) : t)) }];
    }),
  );
  return { ...style, sources };
}

/**
 * The style's GeoJSON sources, and the style with their data left out: the
 * GeoJSON worker gets the data, the map only the source's options.
 */
function splitGeoJSON(style: StyleSpecification): [GeoJSONSource[], StyleSpecification] {
  const found: GeoJSONSource[] = [];
  const sources = Object.fromEntries(
    Object.entries(style.sources ?? {}).map(([id, s]) => {
      const src = s as { type?: unknown; data?: unknown; maxzoom?: unknown; buffer?: unknown; tolerance?: unknown };
      if (src?.type !== "geojson") return [id, s];
      const num = (v: unknown, d: number) => (typeof v === "number" ? v : d);
      found.push({ id, data: src.data, maxzoom: num(src.maxzoom, 18), buffer: num(src.buffer, 128), tolerance: num(src.tolerance, 0.375) });
      return [id, { ...src, data: null }];
    }),
  );
  return [found, { ...style, sources }];
}

function attributions(style: StyleSpecification): string[] {
  const out = new Set<string>();
  for (const s of Object.values(style.sources ?? {})) {
    const a = (s as { attribution?: unknown })?.attribution;
    if (typeof a === "string" && a !== "") out.add(a);
  }
  return [...out];
}

export class Map {
  #container: HTMLElement;
  #canvas: HTMLCanvasElement;
  #attribution: HTMLElement | null = null;
  #engine: engine.EngineMap | null = null;
  #geojson: GeoJSONTiles | null = null;
  #camera: Camera;
  #listeners = new globalThis.Map<MapEventType, Set<MapEventListener>>();
  #loaded = false;
  #removed = false;
  #options: MapOptions;

  constructor(options: MapOptions) {
    const container =
      typeof options.container === "string" ? document.getElementById(options.container) : options.container;
    if (!container) throw new Error(`mbmap: container not found: ${String(options.container)}`);
    this.#container = container;
    this.#options = options;
    const center = toLngLat(options.center ?? [0, 0]);
    this.#camera = checkCamera({
      ...center,
      zoom: options.zoom ?? 0,
      bearing: options.bearing ?? 0,
      pitch: options.pitch ?? 0,
    });
    if (getComputedStyle(container).position === "static") container.style.position = "relative";
    this.#canvas = document.createElement("canvas");
    this.#canvas.style.cssText = "display:block;width:100%;height:100%";
    container.append(this.#canvas);

    if (typeof options.style === "string") {
      const url = new URL(options.style, document.baseURI);
      fetch(url, { credentials: "omit" })
        .then((res) => {
          if (!res.ok) throw new Error(`mbmap: style: HTTP ${res.status}`);
          return res.json() as Promise<StyleSpecification>;
        })
        .then((style) => this.#start(style, url))
        .catch((err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err))));
    } else {
      try {
        this.#start(options.style, new URL(document.baseURI));
      } catch (err) {
        this.#canvas.remove();
        throw err;
      }
    }
  }

  /**
   * Creates the engine, at once or, when the style has GeoJSON sources,
   * once their module is loaded (errors then come as `error` events).
   */
  #start(style: StyleSpecification, base: URL): void {
    if (this.#removed) return;
    const [geojson, rest] = splitGeoJSON(resolveTiles(style, base));
    if (geojson.length === 0) {
      this.#create(rest, null);
      return;
    }
    import("./geojson.js")
      .then(({ createGeoJSONTiles }) => {
        if (this.#removed) return;
        const o = this.#options;
        const tiles = createGeoJSONTiles(geojson, base, (e) => this.#fail(e), {
          workerUrl: o.geojsonWorkerUrl,
          wasmUrl: o.geojsonWasmUrl,
        });
        this.#geojson = tiles;
        this.#create(rest, (source, z, x, y) => tiles.tile(source, z, x, y));
      })
      .catch((err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err))));
  }

  #create(resolved: StyleSpecification, geojson: engine.Provider | null): void {
    const o = this.#options;
    const c = this.#camera;
    const page = new URL(document.baseURI);
    const map = engine.create_map(
      this.#canvas,
      JSON.stringify(resolved),
      c.lng,
      c.lat,
      c.zoom,
      c.bearing,
      c.pitch,
      workerScriptUrl(o.workerUrl ?? new URL("./worker.js", import.meta.url), page, location.origin),
      wasmUrl(o.wasmUrl ?? new URL("./mbmap.wasm", import.meta.url), page),
      o.workerCount ?? 0,
      geojson,
    );
    this.#engine = map;
    engine.map_on_move(map, () => this.#emit("move"));
    engine.map_on_idle(map, () => {
      if (!this.#loaded) {
        this.#loaded = true;
        this.#emit("load");
      }
      this.#emit("idle");
    });
    if (o.attributionControl ?? true) this.#showAttribution(attributions(resolved));
  }

  #showAttribution(texts: string[]): void {
    if (texts.length === 0) return;
    const el = document.createElement("div");
    el.style.cssText =
      "position:absolute;top:auto;left:auto;right:0;bottom:0;padding:0 5px;font:12px/20px sans-serif;" +
      "color:#333;background:rgba(255,255,255,0.7);pointer-events:none";
    // Text only: attribution strings come from the style (AGENTS.md §8.3).
    el.textContent = texts.join(" | ");
    this.#container.append(el);
    this.#attribution = el;
  }

  #fail(error: Error): void {
    if (this.#removed) return;
    if (!this.#listeners.get("error")?.size) console.error(error);
    this.#emit("error", error);
  }

  #emit(type: MapEventType, error?: Error): void {
    const listeners = this.#listeners.get(type);
    if (!listeners) return;
    const event: MapEvent = error ? { type, target: this, error } : { type, target: this };
    for (const f of [...listeners]) {
      try {
        f(event);
      } catch (err) {
        // Report without breaking the engine's frame.
        queueMicrotask(() => {
          throw err;
        });
      }
    }
  }

  on(type: MapEventType, listener: MapEventListener): this {
    let set = this.#listeners.get(type);
    if (!set) this.#listeners.set(type, (set = new Set()));
    set.add(listener);
    return this;
  }

  off(type: MapEventType, listener: MapEventListener): this {
    this.#listeners.get(type)?.delete(listener);
    return this;
  }

  /** Listens for the next `type` event; without a listener, resolves with it. */
  once(type: MapEventType): Promise<MapEvent>;
  once(type: MapEventType, listener: MapEventListener): this;
  once(type: MapEventType, listener?: MapEventListener): this | Promise<MapEvent> {
    if (!listener) return new Promise((resolve) => this.once(type, resolve));
    const wrapped: MapEventListener = (e) => {
      this.off(type, wrapped);
      listener(e);
    };
    return this.on(type, wrapped);
  }

  /** Whether the first view has been drawn. */
  loaded(): boolean {
    return this.#loaded;
  }

  getContainer(): HTMLElement {
    return this.#container;
  }

  getCanvas(): HTMLCanvasElement {
    return this.#canvas;
  }

  #current(): Camera {
    return this.#engine ? engine.map_camera(this.#engine) : { ...this.#camera };
  }

  getCenter(): LngLat {
    const { lng, lat } = this.#current();
    return { lng, lat };
  }

  getZoom(): number {
    return this.#current().zoom;
  }

  getBearing(): number {
    return this.#current().bearing;
  }

  getPitch(): number {
    return this.#current().pitch;
  }

  /** Moves the camera at once; fires `move` unless nothing changes. Throws a TypeError on non-finite values. */
  jumpTo(options: { center?: LngLatLike; zoom?: number; bearing?: number; pitch?: number }): this {
    const c = this.#current();
    const center = options.center ? toLngLat(options.center) : c;
    const next = checkCamera({
      lng: center.lng,
      lat: center.lat,
      zoom: options.zoom ?? c.zoom,
      bearing: options.bearing ?? c.bearing,
      pitch: options.pitch ?? c.pitch,
    });
    if (this.#engine) engine.map_set_camera(this.#engine, next.lng, next.lat, next.zoom, next.bearing, next.pitch);
    else this.#camera = next;
    return this;
  }

  setCenter(center: LngLatLike): this {
    return this.jumpTo({ center });
  }

  setZoom(zoom: number): this {
    return this.jumpTo({ zoom });
  }

  setBearing(bearing: number): this {
    return this.jumpTo({ bearing });
  }

  /** Clamped to 0-60 degrees. */
  setPitch(pitch: number): this {
    return this.jumpTo({ pitch });
  }

  /** Stops the workers, frees GPU memory and removes the map's elements. */
  remove(): void {
    if (this.#removed) return;
    this.#removed = true;
    if (this.#engine) engine.map_destroy(this.#engine);
    this.#engine = null;
    this.#geojson?.terminate();
    this.#geojson = null;
    this.#listeners.clear();
    this.#canvas.remove();
    this.#attribution?.remove();
  }
}
