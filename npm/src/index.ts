import * as engine from "mbmap-engine";

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
  /** Tile workers; 0 (the default) picks half the hardware threads, 1 to 4. */
  workerCount?: number;
  /**
   * Where the worker script and its wasm are served. They default to the
   * files next to this module, which suits bundlers that understand
   * `new URL(..., import.meta.url)` and plain ESM serving. Module workers
   * must be same-origin with the page.
   */
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
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
}

function toLngLat(c: LngLatLike): LngLat {
  return Array.isArray(c) ? { lng: c[0], lat: c[1] } : { lng: c.lng, lat: c.lat };
}

// URL() percent-encodes the braces of {z}/{x}/{y}; put them back.
function resolveTemplate(template: string, base: URL): string {
  return new URL(template, base).href.replace(/%7B([zxy])%7D/g, "{$1}");
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
    this.#camera = { ...center, zoom: options.zoom ?? 0 };
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

  #start(style: StyleSpecification, base: URL): void {
    if (this.#removed) return;
    const resolved = resolveTiles(style, base);
    const o = this.#options;
    const c = this.#camera;
    const map = engine.create_map(
      this.#canvas,
      JSON.stringify(resolved),
      c.lng,
      c.lat,
      c.zoom,
      new URL(o.workerUrl ?? new URL("./worker.js", import.meta.url), document.baseURI).href,
      new URL(o.wasmUrl ?? new URL("./mbmap.wasm", import.meta.url), document.baseURI).href,
      o.workerCount ?? 0,
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

  /** Moves the camera at once; fires `move` unless nothing changes. */
  jumpTo(options: { center?: LngLatLike; zoom?: number }): this {
    const c = this.#current();
    const center = options.center ? toLngLat(options.center) : c;
    const next = { lng: center.lng, lat: center.lat, zoom: options.zoom ?? c.zoom };
    if (this.#engine) engine.map_set_camera(this.#engine, next.lng, next.lat, next.zoom);
    else this.#camera = next;
    return this;
  }

  setCenter(center: LngLatLike): this {
    return this.jumpTo({ center });
  }

  setZoom(zoom: number): this {
    return this.jumpTo({ zoom });
  }

  /** Stops the workers, frees GPU memory and removes the map's elements. */
  remove(): void {
    if (this.#removed) return;
    this.#removed = true;
    if (this.#engine) engine.map_destroy(this.#engine);
    this.#engine = null;
    this.#listeners.clear();
    this.#canvas.remove();
    this.#attribution?.remove();
  }
}
