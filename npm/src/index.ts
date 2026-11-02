import * as engine from "mbmap-engine";
import {
  type EaseToOptions,
  type FitBoundsOptions,
  type FlyToOptions,
  HANDLERS,
  type HandlerName,
  type LngLat,
  LngLatBounds,
  type LngLatBoundsLike,
  type LngLatLike,
  type Limits,
  type PointLike,
  fitArray,
  flyArray,
  limitsArray,
  targetArray,
  toLngLat,
  toPoint,
} from "./camera";
import type { GeoJSONSource, GeoJSONTiles } from "./geojson";
import * as edit from "./style";
import type { LayerSpecification, StyleSpecification } from "./style";
import { resolveTemplate, wasmUrl, workerScriptUrl } from "./urls";

export { LngLatBounds } from "./camera";
export type {
  AnimationOptions,
  CameraOptions,
  EaseToOptions,
  FitBoundsOptions,
  FlyToOptions,
  HandlerName,
  LngLat,
  LngLatBoundsLike,
  LngLatLike,
  PaddingOptions,
  PointLike,
} from "./camera";

export type { LayerSpecification, StyleSpecification } from "./style";

/** What `getSource` gives: a GeoJSON source also takes new data. */
export interface Source {
  id: string;
  type: string;
  setData?(data: unknown): void;
}

/**
 * - `container`: the element (or its id) the map fills. It needs a size of its own.
 * - `style`: a style object, or the URL of one (fetched without credentials).
 * - `bearing`: degrees clockwise from north that point up (default 0).
 * - `pitch`: degrees of tilt from looking straight down, 0 to 85 (default 0).
 * - `workerCount`: tile workers; 0 (the default) picks half the hardware threads, 1 to 4.
 * - `workerUrl`, `wasmUrl`: where the worker (same-origin http(s)) and its wasm
 *   (http(s)) are served; by default next to this module, via `new URL(..., import.meta.url)`.
 * - `geojsonWorkerUrl`, `geojsonWasmUrl`: the same for the worker of GeoJSON sources.
 * - `fontFamily`: the CSS font family labels are drawn in, from the fonts the browser has (default "sans-serif").
 * - `attributionControl`: shows the sources' `attribution` text in a corner (default true).
 * - `minZoom`, `maxZoom` (0 and 22), `minPitch`, `maxPitch` (0 and 85), `maxBounds`: what the camera keeps to.
 * - `bounds`, `fitBoundsOptions`: a box to show at first, in place of `center` and `zoom`.
 * - `interactive: false` turns every input off; `dragPan`, `scrollZoom`, `boxZoom`, `dragRotate`,
 *   `keyboard`, `doubleClickZoom`, `touchZoomRotate`, `touchPitch` (all true) one by one.
 */
export interface MapOptions {
  container: HTMLElement | string;
  style: StyleSpecification | string;
  center?: LngLatLike;
  zoom?: number;
  bearing?: number;
  pitch?: number;
  workerCount?: number;
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
  geojsonWorkerUrl?: string | URL;
  geojsonWasmUrl?: string | URL;
  fontFamily?: string;
  attributionControl?: boolean;
  minZoom?: number;
  maxZoom?: number;
  minPitch?: number;
  maxPitch?: number;
  maxBounds?: LngLatBoundsLike;
  bounds?: LngLatBoundsLike;
  fitBoundsOptions?: FitBoundsOptions;
  interactive?: boolean;
  dragPan?: boolean;
  scrollZoom?: boolean;
  boxZoom?: boolean;
  dragRotate?: boolean;
  keyboard?: boolean;
  doubleClickZoom?: boolean;
  touchZoomRotate?: boolean;
  touchPitch?: boolean;
}

export type MapEventType =
  | "load"
  | "idle"
  | "error"
  | "movestart"
  | "move"
  | "moveend"
  | "zoomstart"
  | "zoom"
  | "zoomend"
  | "rotatestart"
  | "rotate"
  | "rotateend"
  | "pitchstart"
  | "pitch"
  | "pitchend";

/**
 * `load` fires once, at the first drawn view; `idle` when the map settles. Camera changes fire
 * `movestart`, `move` (and `zoom`, `rotate`, `pitch` with their own start and end) and `moveend`,
 * as in MapLibre; `originalEvent` is the DOM event of a user's gesture.
 */
export interface MapEvent {
  type: MapEventType;
  target: Map;
  error?: Error;
  originalEvent?: Event;
}

export type MapEventListener = (event: MapEvent) => void;

interface Camera {
  lng: number;
  lat: number;
  zoom: number;
  bearing: number;
  pitch: number;
}

/** One input handler: `enable`, `disable`, `isEnabled`, as MapLibre's `map.scrollZoom` and the like. */
export interface Handler {
  enable(): void;
  disable(): void;
  isEnabled(): boolean;
}

/** MapLibre's default easing, the CSS `ease` curve (0.25, 0.1, 0.25, 1). */
function defaultEasing(t: number): number {
  return engine.default_easing(t);
}

/** Whether the user asked the system for less motion (MapLibre then skips animations). */
function reducedMotion(): boolean {
  return typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
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

/** The style's GeoJSON sources, and the style without their data (only their worker needs it). */
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
  #geojsonLoading: Promise<GeoJSONTiles | null> | null = null;
  #geojsonSources: GeoJSONSource[] = [];
  #style: StyleSpecification | null = null;
  #base = new URL(document.baseURI);
  #styleRequest = 0;
  #camera: Camera;
  #listeners = new globalThis.Map<MapEventType, Set<MapEventListener>>();
  #loaded = false;
  #removed = false;
  #options: MapOptions;
  #limits: Limits;
  #enabled: Record<HandlerName, boolean>;
  #callsBeforeStart: (() => void)[] = [];
  #changing = { zoom: false, rotate: false, pitch: false };
  #last: Camera | null = null;
  readonly dragPan: Handler;
  readonly scrollZoom: Handler;
  readonly boxZoom: Handler;
  readonly dragRotate: Handler;
  readonly keyboard: Handler;
  readonly doubleClickZoom: Handler;
  readonly touchZoomRotate: Handler;
  readonly touchPitch: Handler;

  constructor(options: MapOptions) {
    const container =
      typeof options.container === "string" ? document.getElementById(options.container) : options.container;
    if (!container) throw new Error(`mbmap: container not found: ${String(options.container)}`);
    this.#container = container;
    this.#options = options;
    this.#limits = {
      minZoom: options.minZoom ?? 0,
      maxZoom: options.maxZoom ?? 22,
      minPitch: options.minPitch ?? 0,
      maxPitch: options.maxPitch ?? 85,
      maxBounds: options.maxBounds ? LngLatBounds.convert(options.maxBounds) : null,
    };
    const interactive = options.interactive ?? true;
    this.#enabled = Object.fromEntries(HANDLERS.map((h) => [h, interactive && (options[h] ?? true)])) as Record<HandlerName, boolean>;
    const handler = (name: HandlerName): Handler => ({
      enable: () => this.#setHandler(name, true),
      disable: () => this.#setHandler(name, false),
      isEnabled: () => this.#enabled[name],
    });
    this.dragPan = handler("dragPan");
    this.scrollZoom = handler("scrollZoom");
    this.boxZoom = handler("boxZoom");
    this.dragRotate = handler("dragRotate");
    this.keyboard = handler("keyboard");
    this.doubleClickZoom = handler("doubleClickZoom");
    this.touchZoomRotate = handler("touchZoomRotate");
    this.touchPitch = handler("touchPitch");
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

    try {
      this.setStyle(options.style);
    } catch (err) {
      this.#canvas.remove();
      throw err;
    }
  }

  /**
   * Draws `style` (an object, or a URL fetched without credentials) from now on. Sources
   * and layers that stay alike keep their tiles; the rest load again while the old ones
   * are drawn. A style that cannot be drawn fires `error` and the current one stays.
   */
  setStyle(style: StyleSpecification | string): this {
    const request = ++this.#styleRequest;
    const use = (s: StyleSpecification, base: URL) => {
      if (request !== this.#styleRequest || this.#removed) return;
      const next = edit.keepGeoJSONData(this.#style, edit.copy(s));
      this.#base = base;
      if (this.#engine) this.#apply(next);
      else this.#create(next);
    };
    if (typeof style === "string") {
      const url = new URL(style, document.baseURI);
      fetch(url, { credentials: "omit" })
        .then((res) => {
          if (!res.ok) throw new Error(`mbmap: style: HTTP ${res.status}`);
          return res.json() as Promise<StyleSpecification>;
        })
        .then((s) => use(s, url))
        .catch((err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err))));
    } else {
      use(style, new URL(document.baseURI));
    }
    return this;
  }

  /** A copy of the style drawn, GeoJSON data included (null until it has loaded). */
  getStyle(): StyleSpecification | null {
    return edit.copy(this.#style);
  }

  /** Swaps in `next`, an edit of the current style; a style the engine refuses fires `error`. */
  #apply(next: StyleSpecification): void {
    if (!this.#engine) return;
    const [geojson, rest] = splitGeoJSON(resolveTiles(next, this.#base));
    const refused = engine.map_set_style(this.#engine, JSON.stringify(rest));
    if (refused) {
      this.#fail(new Error(refused));
      return;
    }
    this.#style = next;
    for (const id of this.#loadGeoJSON(geojson)) engine.map_reload_source(this.#engine, id);
    this.#showAttribution(attributions(rest));
  }

  /** Runs `f` on the current style and draws what it gives; its errors fire `error`. */
  #edit(f: (style: StyleSpecification) => StyleSpecification): this {
    if (!this.#style) throw new Error("mbmap: the style has not loaded yet");
    let next: StyleSpecification;
    try {
      next = f(this.#style);
    } catch (err) {
      this.#fail(err instanceof Error ? err : new Error(String(err)));
      return this;
    }
    this.#apply(next);
    return this;
  }

  addLayer(layer: LayerSpecification, beforeId?: string): this {
    return this.#edit((s) => edit.addLayer(s, layer, beforeId));
  }

  removeLayer(id: string): this {
    return this.#edit((s) => edit.removeLayer(s, id));
  }

  /** Moves layer `id` before `beforeId`, or on top. */
  moveLayer(id: string, beforeId?: string): this {
    return this.#edit((s) => edit.moveLayer(s, id, beforeId));
  }

  getLayer(id: string): LayerSpecification | undefined {
    return this.#style ? edit.copy(edit.getLayer(this.#style, id)) : undefined;
  }

  /** The layer ids, bottom first. */
  getLayersOrder(): string[] {
    return this.#style ? (this.#style.layers as LayerSpecification[]).map((l) => l.id) : [];
  }

  setPaintProperty(id: string, name: string, value: unknown): this {
    return this.#edit((s) => edit.setPaintProperty(s, id, name, value));
  }

  getPaintProperty(id: string, name: string): unknown {
    return this.#style ? edit.getPaintProperty(this.#style, id, name) : undefined;
  }

  setLayoutProperty(id: string, name: string, value: unknown): this {
    return this.#edit((s) => edit.setLayoutProperty(s, id, name, value));
  }

  getLayoutProperty(id: string, name: string): unknown {
    return this.#style ? edit.getLayoutProperty(this.#style, id, name) : undefined;
  }

  /** Sets layer `id`'s filter; null or undefined removes it. */
  setFilter(id: string, filter?: unknown): this {
    return this.#edit((s) => edit.setFilter(s, id, filter));
  }

  getFilter(id: string): unknown {
    return this.#style ? edit.getFilter(this.#style, id) : undefined;
  }

  setLayerZoomRange(id: string, minzoom: number, maxzoom: number): this {
    return this.#edit((s) => edit.setLayerZoomRange(s, id, minzoom, maxzoom));
  }

  addSource(id: string, source: unknown): this {
    return this.#edit((s) => edit.addSource(s, id, source));
  }

  /** Removes source `id`; fires `error` while a layer or the terrain uses it. */
  removeSource(id: string): this {
    return this.#edit((s) => edit.removeSource(s, id));
  }

  /** Source `id`; a GeoJSON one has `setData` to replace its data (an object or a URL). */
  getSource(id: string): Source | undefined {
    const s = this.#style?.sources[id] as { type?: unknown } | undefined;
    if (!s || typeof s.type !== "string") return undefined;
    const source: Source = { id, type: s.type };
    if (s.type === "geojson") source.setData = (data) => void this.#edit((st) => edit.setSourceData(st, id, data));
    return source;
  }

  /** `{source, exaggeration}` draws the ground raised by a `raster-dem` source; null flattens it. */
  setTerrain(terrain: { source: string; exaggeration?: number } | null): this {
    return this.#edit((s) => edit.setRoot(s, "terrain", terrain));
  }

  getTerrain(): unknown {
    return edit.copy(this.#style?.terrain ?? null);
  }

  setSky(sky: Record<string, unknown> | null): this {
    return this.#edit((s) => edit.setRoot(s, "sky", sky));
  }

  getSky(): unknown {
    return edit.copy(this.#style?.sky ?? null);
  }

  setLight(light: Record<string, unknown> | null): this {
    return this.#edit((s) => edit.setRoot(s, "light", light));
  }

  getLight(): unknown {
    return edit.copy(this.#style?.light ?? null);
  }

  /**
   * Hands the GeoJSON sources to their worker, which starts (loading its module) with the
   * first style that has one; returns the ids of sources it loaded again.
   */
  #loadGeoJSON(sources: GeoJSONSource[]): string[] {
    this.#geojsonSources = sources;
    if (this.#geojson) return this.#geojson.set(sources, this.#base);
    if (sources.length > 0 && !this.#geojsonLoading) {
      this.#geojsonLoading = import("./geojson.js").then(
        ({ createGeoJSONTiles }) => {
          if (this.#removed) return null;
          const o = this.#options;
          this.#geojson = createGeoJSONTiles(this.#geojsonSources, this.#base, (e) => this.#fail(e), {
            workerUrl: o.geojsonWorkerUrl,
            wasmUrl: o.geojsonWasmUrl,
          });
          return this.#geojson;
        },
        (err: unknown) => {
          this.#fail(err instanceof Error ? err : new Error(String(err)));
          return null;
        },
      );
    }
    return [];
  }

  /** A GeoJSON tile for the engine, once the GeoJSON worker has started. */
  #geojsonTile(source: string, z: number, x: number, y: number): Promise<ArrayBuffer | null> {
    if (this.#geojson) return this.#geojson.tile(source, z, x, y);
    return this.#geojsonLoading?.then((t) => t?.tile(source, z, x, y) ?? null) ?? Promise.resolve(null);
  }

  #create(style: StyleSpecification): void {
    const [geojson, resolved] = splitGeoJSON(resolveTiles(style, this.#base));
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
      (source, z, x, y) => this.#geojsonTile(source, z, x, y),
      o.fontFamily ?? "sans-serif",
      limitsArray(this.#limits),
    );
    this.#engine = map;
    this.#style = style;
    this.#loadGeoJSON(geojson);
    HANDLERS.forEach((h, i) => engine.map_set_handler(map, i, this.#enabled[h]));
    engine.map_on_move_start(map, (e) => this.#moveStart(e));
    engine.map_on_move(map, () => this.#move(engine.map_input_event(map)));
    engine.map_on_move_end(map, (e) => this.#moveEnd(e));
    engine.map_on_idle(map, () => {
      if (!this.#loaded) {
        this.#loaded = true;
        this.#emit("load");
      }
      this.#emit("idle");
    });
    this.#showAttribution(attributions(resolved));
    if (o.bounds) this.fitBounds(o.bounds, { ...o.fitBoundsOptions, duration: 0 });
    for (const f of this.#callsBeforeStart.splice(0)) f();
  }

  #setHandler(name: HandlerName, on: boolean): void {
    this.#enabled[name] = on;
    if (this.#engine) engine.map_set_handler(this.#engine, HANDLERS.indexOf(name), on);
  }

  #moveStart(e: Event | null): void {
    this.#last = this.#current();
    this.#emit("movestart", undefined, e);
  }

  #move(e: Event | null): void {
    const c = this.#current();
    const last = this.#last ?? c;
    const changed = (["zoom", "rotate", "pitch"] as const).filter((k, i) => [c.zoom !== last.zoom, c.bearing !== last.bearing, c.pitch !== last.pitch][i]);
    // As MapLibre: starts, then `move`, then what changed.
    for (const kind of changed) {
      if (!this.#changing[kind]) {
        this.#changing[kind] = true;
        this.#emit(`${kind}start`, undefined, e);
      }
    }
    this.#emit("move", undefined, e);
    for (const kind of changed) this.#emit(kind, undefined, e);
    this.#last = c;
  }

  #moveEnd(e: Event | null): void {
    for (const kind of ["zoom", "rotate", "pitch"] as const) {
      if (this.#changing[kind]) {
        this.#changing[kind] = false;
        this.#emit(`${kind}end`, undefined, e);
      }
    }
    this.#last = null;
    this.#emit("moveend", undefined, e);
  }

  #showAttribution(texts: string[]): void {
    this.#attribution?.remove();
    this.#attribution = null;
    if (texts.length === 0 || !(this.#options.attributionControl ?? true)) return;
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

  #emit(type: MapEventType, error?: Error, originalEvent?: Event | null): void {
    const listeners = this.#listeners.get(type);
    if (!listeners) return;
    const event: MapEvent = { type, target: this };
    if (error) event.error = error;
    if (originalEvent) event.originalEvent = originalEvent;
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

  /** Clamped to the pitch range (0-85 degrees by default). */
  setPitch(pitch: number): this {
    return this.jumpTo({ pitch });
  }

  /** Runs `f` on the engine now, or once it exists. */
  #withEngine(f: (map: engine.EngineMap) => void): this {
    if (this.#engine) f(this.#engine);
    else this.#callsBeforeStart.push(() => this.#engine && f(this.#engine));
    return this;
  }

  /** Eases to the camera `options` give (MapLibre's `easeTo`: 500 ms by default). */
  easeTo(options: EaseToOptions): this {
    const target = targetArray(options);
    const jump = options.animate === false || (!options.essential && reducedMotion());
    const duration = jump ? 0 : options.duration ?? 500;
    return this.#withEngine((m) => engine.map_ease_to(m, target, duration, options.easing ?? defaultEasing, ""));
  }

  /** Flies to the camera `options` give, zooming out and back in (MapLibre's `flyTo`). */
  flyTo(options: FlyToOptions): this {
    if (options.animate === false || (!options.essential && reducedMotion())) return this.easeTo(options);
    const target = targetArray(options);
    const fly = flyArray(options);
    return this.#withEngine((m) => engine.map_fly_to(m, target, fly, options.easing ?? defaultEasing));
  }

  panBy(offset: PointLike, options: EaseToOptions = {}): this {
    const p = toPoint(offset);
    return this.panTo(this.getCenter(), { offset: [-p.x, -p.y], ...options });
  }

  panTo(center: LngLatLike, options: EaseToOptions = {}): this {
    return this.easeTo({ ...options, center });
  }

  zoomTo(zoom: number, options: EaseToOptions = {}): this {
    return this.easeTo({ ...options, zoom });
  }

  zoomIn(options: EaseToOptions = {}): this {
    return this.zoomTo(this.getZoom() + 1, options);
  }

  zoomOut(options: EaseToOptions = {}): this {
    return this.zoomTo(this.getZoom() - 1, options);
  }

  rotateTo(bearing: number, options: EaseToOptions = {}): this {
    return this.easeTo({ ...options, bearing });
  }

  resetNorth(options: EaseToOptions = {}): this {
    return this.rotateTo(0, { duration: 1000, ...options });
  }

  resetNorthPitch(options: EaseToOptions = {}): this {
    return this.easeTo({ bearing: 0, pitch: 0, duration: 1000, ...options });
  }

  /** Resets the bearing to north if it is within 7° of it (MapLibre's `bearingSnap`). */
  snapToNorth(options: EaseToOptions = {}): this {
    return Math.abs(this.getBearing()) < 7 ? this.resetNorth(options) : this;
  }

  /**
   * The camera that shows `bounds` (MapLibre's `cameraForBounds`), or undefined when the
   * padding leaves no room or the map has not started.
   */
  cameraForBounds(bounds: LngLatBoundsLike, options: FitBoundsOptions = {}): { center: LngLat; zoom: number; bearing: number } | undefined {
    if (!this.#engine) return undefined;
    const c = engine.map_camera_for_bounds(this.#engine, fitArray(LngLatBounds.convert(bounds), options));
    return c.length ? { center: { lng: c[0], lat: c[1] }, zoom: c[2], bearing: c[3] } : undefined;
  }

  /** Moves to show `bounds`: a flight, or an ease with `linear: true` (MapLibre's `fitBounds`). */
  fitBounds(bounds: LngLatBoundsLike, options: FitBoundsOptions = {}): this {
    const b = LngLatBounds.convert(bounds);
    return this.#withEngine(() => {
      const c = this.cameraForBounds(b, options);
      if (!c) return;
      const { padding: _, maxZoom: __, linear, ...rest } = options;
      const target = { ...rest, center: c.center, zoom: c.zoom, bearing: c.bearing, offset: undefined };
      if (linear) this.easeTo(target);
      else this.flyTo(target);
    });
  }

  /** Moves to show the box between two screen points, turned to `bearing` (MapLibre's `fitScreenCoordinates`). */
  fitScreenCoordinates(p0: PointLike, p1: PointLike, bearing: number, options: FitBoundsOptions = {}): this {
    return this.#withEngine(() => {
      const a = this.unproject(p0);
      const b = this.unproject(p1);
      const box = new LngLatBounds(Math.min(a.lng, b.lng), Math.min(a.lat, b.lat), Math.max(a.lng, b.lng), Math.max(a.lat, b.lat));
      this.fitBounds(box, { ...options, bearing });
    });
  }

  /** Stops a camera animation. */
  stop(): this {
    if (this.#engine) engine.map_stop(this.#engine);
    return this;
  }

  /** Whether the camera is moving: a gesture, its inertia or an animation. */
  isMoving(): boolean {
    return !!this.#engine && engine.map_motion(this.#engine) > 0;
  }

  /** Whether a camera animation is running. */
  isEasing(): boolean {
    return !!this.#engine && engine.map_motion(this.#engine) === 2;
  }

  isZooming(): boolean {
    return this.#changing.zoom;
  }

  isRotating(): boolean {
    return this.#changing.rotate;
  }

  /** The screen point (CSS pixels from the top-left corner) of `lnglat` on the ground. */
  project(lnglat: LngLatLike): { x: number; y: number } {
    const p = toLngLat(lnglat);
    if (!this.#engine) return { x: NaN, y: NaN };
    const [x, y] = engine.map_project(this.#engine, p.lng, p.lat);
    return { x, y };
  }

  /** The ground point under screen point `point`. */
  unproject(point: PointLike): LngLat {
    const p = toPoint(point);
    if (!this.#engine) return { lng: NaN, lat: NaN };
    const [lng, lat] = engine.map_unproject(this.#engine, p.x, p.y);
    return { lng, lat };
  }

  /** The box around what the map shows (up to the horizon when tilted). */
  getBounds(): LngLatBounds {
    if (!this.#engine) return new LngLatBounds(NaN, NaN, NaN, NaN);
    const [w, s, e, n] = engine.map_bounds(this.#engine);
    return new LngLatBounds(w, s, e, n);
  }

  #setLimits(change: Partial<Limits>): this {
    const next = { ...this.#limits, ...change };
    for (const v of [next.minZoom, next.maxZoom, next.minPitch, next.maxPitch]) {
      if (!Number.isFinite(v)) throw new TypeError(`mbmap: zoom and pitch limits must be finite numbers: ${String(v)}`);
    }
    if (next.minZoom > next.maxZoom || next.minPitch > next.maxPitch || next.minZoom < 0 || next.maxZoom > 24 || next.minPitch < 0 || next.maxPitch > 85) {
      throw new RangeError("mbmap: zoom limits must lie in 0-24 and pitch limits in 0-85, min not above max");
    }
    this.#limits = next;
    if (this.#engine) engine.map_set_limits(this.#engine, limitsArray(next));
    return this;
  }

  setMinZoom(zoom?: number | null): this {
    return this.#setLimits({ minZoom: zoom ?? 0 });
  }

  getMinZoom(): number {
    return this.#limits.minZoom;
  }

  setMaxZoom(zoom?: number | null): this {
    return this.#setLimits({ maxZoom: zoom ?? 22 });
  }

  getMaxZoom(): number {
    return this.#limits.maxZoom;
  }

  setMinPitch(pitch?: number | null): this {
    return this.#setLimits({ minPitch: pitch ?? 0 });
  }

  getMinPitch(): number {
    return this.#limits.minPitch;
  }

  setMaxPitch(pitch?: number | null): this {
    return this.#setLimits({ maxPitch: pitch ?? 85 });
  }

  getMaxPitch(): number {
    return this.#limits.maxPitch;
  }

  /** Keeps the view inside `bounds` (null lifts it). */
  setMaxBounds(bounds?: LngLatBoundsLike | null): this {
    return this.#setLimits({ maxBounds: bounds ? LngLatBounds.convert(bounds) : null });
  }

  getMaxBounds(): LngLatBounds | null {
    return this.#limits.maxBounds;
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
