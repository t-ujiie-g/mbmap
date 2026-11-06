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
  MAX_PITCH,
  MAX_ZOOM,
  MIN_PITCH,
  MIN_ZOOM,
  checkLimits,
  fitArray,
  flyArray,
  limitsArray,
  targetArray,
  toLngLat,
  toPoint,
} from "./camera";
import type { ClusterQuery, GeoJSONSource, GeoJSONTiles } from "./geojson";
import type { Media, UpdateImageOptions } from "./media";
import type { CustomLayerInterface, CustomLayers } from "./custom";
import { type GeoJSONFeature, orderRendered, queryArgs, queryLayers, queryPoints } from "./query";
import { filterText as engineFilter, resolveTiles, splitGeoJSON } from "./engine-style";
import { removeStateError, stateIdError, stateLayer } from "./feature-state";
import * as edit from "./style";
import type { LayerSpecification, StyleSpecification } from "./style";
import { attributionsOf } from "./attribution";
import { Events } from "./events";
import { GEOTIFF, tileJSONUrls, withoutSources } from "./tilejson";
import type {
  MapGeoJSONFeature,
  FeatureIdentifier,
  QueryRenderedFeaturesOptions,
  QuerySourceFeatureOptions,
  ResourceType,
  RequestTransformFunction,
  Source,
  MapOptions,
  MapMouseEventType,
  MapEventType,
  MapEvent,
  MapEventListener,
  StyleSwapOptions,
  PaintValues,
  ScreenPosition,
  ToBlobOptions,
  Tracker,
  Handler,
} from "./types";
import { httpUrl, pmtilesArchive, resolveTemplate, wasmUrl, workerScriptUrl } from "./urls";
import type { ImageInput, StyleImageOptions } from "./images";
import { StyleImages } from "./style-images";

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
export type { CustomLayerInterface, CustomRenderMethodInput, ProjectionData } from "./custom";
export type { GeoJSONFeature } from "./query";
export type {
  MapGeoJSONFeature,
  FeatureIdentifier,
  QueryRenderedFeaturesOptions,
  QuerySourceFeatureOptions,
  ResourceType,
  RequestTransformFunction,
  Source,
  MapOptions,
  MapMouseEventType,
  MapEventType,
  MapEvent,
  MapEventListener,
  StyleSwapOptions,
  PaintValues,
  ScreenPosition,
  ToBlobOptions,
  Tracker,
  Handler,
} from "./types";

interface Tracked {
  lnglat: LngLat;
  f: (position: ScreenPosition) => void;
}

interface Camera {
  lng: number;
  lat: number;
  zoom: number;
  bearing: number;
  pitch: number;
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

/** `legacy.js` once loaded; only styles with legacy filters or property functions load it. */
let legacy: typeof import("./legacy") | null = null;
let legacyLoading: Promise<unknown> | null = null;

function loadLegacy(): Promise<unknown> {
  legacyLoading ??= import("./legacy.js").then((m) => (legacy = m));
  return legacyLoading;
}

/** `tilejson-merge.js` once loaded, with the first TileJSON document or PMTiles header fetched. */
let tilejson: typeof import("./tilejson-merge") | null = null;

/** A query's filter as the engine takes it, legacy filters converted once `legacy.js` has loaded. */
function filterText(filter: unknown): string {
  return engineFilter(filter, legacy && legacy.convertFilter);
}

export class Map {
  #container: HTMLElement;
  #canvas: HTMLCanvasElement;
  #attribution: HTMLElement | null = null;
  #attributions: string[] = [];
  /** The style as the engine draws it (TileJSON merged), whose sources the attributions come from. */
  #drawn: StyleSpecification | null = null;
  #warned = "";
  #engine: engine.EngineMap | null = null;
  #geojson: GeoJSONTiles | null = null;
  #geojsonLoading: Promise<GeoJSONTiles | null> | null = null;
  #geojsonSources: GeoJSONSource[] = [];
  #media: Media | null = null;
  #mediaLoading: Promise<unknown> | null = null;
  #custom: CustomLayers | null = null;
  #customLoading: Promise<unknown> | null = null;
  /** Canvas sources given an element, which the style's JSON copies cannot hold. */
  #canvases = new globalThis.Map<string, unknown>();
  #style: StyleSpecification | null = null;
  #globalState: Record<string, unknown> = {};
  #base = new URL(document.baseURI);
  #styleRequest = 0;
  #tilejson = new globalThis.Map<string, unknown>();
  #transform: RequestTransformFunction | null = null;
  #camera: Camera;
  #events = new Events(this, (p, layers) => this.#query([p.x, p.y], layers, undefined));
  #tracked = new Set<Tracked>();
  #loaded = false;
  #fetching = 0;
  #images = new StyleImages({
    withEngine: (f) => this.#withEngine(f),
    fail: (err) => this.#fail(err),
    fetch: (url, type) => this.#fetch(url, type),
    waitFor: (p) => this.#waitFor(p),
  });
  #removed = false;
  #options: MapOptions;
  #limits: Limits;
  #enabled: Record<HandlerName, boolean>;
  #callsBeforeStart: (() => void)[] = [];
  #changing = { zoom: false, rotate: false, pitch: false };
  #dom = new AbortController();
  #states = new globalThis.Map<string, globalThis.Map<string, globalThis.Map<string, Record<string, unknown>>>>();
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
      minZoom: options.minZoom ?? MIN_ZOOM,
      maxZoom: options.maxZoom ?? MAX_ZOOM,
      minPitch: options.minPitch ?? MIN_PITCH,
      maxPitch: options.maxPitch ?? MAX_PITCH,
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
    this.#transform = options.transformRequest ?? null;
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
  setStyle(style: StyleSpecification | string, options: StyleSwapOptions = {}): this {
    const request = ++this.#styleRequest;
    const use = (s: StyleSpecification, base: URL) => {
      if (request !== this.#styleRequest || this.#removed) return;
      let swapped = s;
      if (options.transformStyle) {
        try {
          swapped = options.transformStyle(edit.copy(this.#style && edit.withoutCustom(this.#style)) ?? undefined, edit.copy(s)!);
        } catch (err) {
          this.#fail(err);
          return;
        }
      }
      const next = edit.keepGeoJSONData(this.#style, edit.copy(swapped));
      if (!legacy && edit.hasLegacy(next)) {
        loadLegacy()
          .then(() => use(s, base))
          .catch((err: unknown) => this.#fail(err));
        return;
      }
      this.#base = base;
      const state = this.#globalState;
      this.#globalState = edit.loadedState(state, next, this.#options.globalState ?? {});
      if (this.#engine) this.#apply(next);
      else this.#create(next);
      if (this.#style !== next) this.#globalState = state;
    };
    // Sources given by TileJSON wait for their documents.
    const ready = (s: StyleSpecification, base: URL) => {
      const missing = this.#missingTileJSON(s, base);
      if (missing.length === 0) return use(s, base);
      this.#fetchTileJSON(missing, () => use(s, base)).catch((err: unknown) => this.#fail(err));
    };
    if (typeof style === "string") {
      const url = new URL(httpUrl(style, document.baseURI, "the style"));
      this.#fetch(url.href, "Style")
        .then((res) => {
          if (!res.ok) throw new Error(`mbmap: style: HTTP ${res.status}`);
          return res.json() as Promise<StyleSpecification>;
        })
        .then((s) => ready(s, url))
        .catch((err: unknown) => this.#fail(err));
    } else {
      this.#keepCanvases(style.sources);
      ready(style, new URL(document.baseURI));
    }
    return this;
  }

  #keepCanvases(sources: Record<string, unknown> | undefined): void {
    for (const [id, s] of Object.entries(sources ?? {})) {
      const canvas = (s as { canvas?: unknown })?.canvas;
      if (canvas && typeof canvas === "object") this.#canvases.set(id, canvas);
    }
  }

  /** Hands the style's image, video and canvas sources to `media.js`, loaded with the first one. */
  #syncMedia(style: StyleSpecification): void {
    const sources = Object.entries(style.sources ?? {})
      .filter(([, s]) => ["image", "video", "canvas"].includes((s as { type?: string })?.type ?? ""))
      .map(([id, spec]) => ({ id, spec: spec as Record<string, unknown>, canvas: this.#canvases.get(id) }));
    if (sources.length > 0 || this.#media) this.#withMedia((m) => m.set(sources, this.#base));
  }

  #withMedia(f: (m: Media) => void): void {
    if (this.#media) return f(this.#media);
    this.#mediaLoading ??= import("./media.js").then(({ Media }) => {
      const on = (f: (m: engine.EngineMap) => void) => this.#engine && f(this.#engine);
      this.#media = new Media(
        {
          show: (s, p, q) => on((m) => engine.map_set_media(m, s, p, q)),
          move: (s, q) => on((m) => engine.map_set_media_quad(m, s, q)),
          playing: (s, playing) => on((m) => engine.map_set_media_playing(m, s, playing)),
        },
        (url) => this.#fetch(url, "Image"),
        (e) => this.#fail(e),
      );
    });
    this.#mediaLoading.then(
      () => !this.#removed && f(this.#media!),
      (err: unknown) => this.#fail(err),
    );
  }

  /** Fetches `url` through the `transformRequest`, without credentials unless it asks for them. */
  #fetch(url: string, type: ResourceType): Promise<Response> {
    const r = this.#transform?.(url, type);
    return r ? fetch(r.url, { headers: r.headers, credentials: r.credentials ?? "omit" }) : fetch(url, { credentials: "omit" });
  }

  /** Sets the `transformRequest` (null for none); tiles asked for from now on go through it. */
  setTransformRequest(transform: RequestTransformFunction | null): this {
    this.#transform = transform;
    return this.#withEngine((m) => engine.map_set_transform_request(m, transform));
  }

  /** The TileJSON URLs of `style` not fetched yet. */
  #missingTileJSON(style: StyleSpecification, base: URL): string[] {
    return [...tileJSONUrls(style, base).values()].filter((u) => !this.#tilejson.has(u));
  }

  /** Fetches TileJSON documents (without credentials), or PMTiles headers, into the cache, then runs `use`: `idle` waits for both. */
  #fetchTileJSON(urls: string[], use: () => void): Promise<void> {
    return this.#waitFor(this.#fetchDocuments(urls).then(use));
  }

  /** Holds `load` and `idle` back until `p` settles; they come then if the engine is idle. */
  #waitFor<T>(p: Promise<T>): Promise<T> {
    this.#fetching++;
    return p.finally(() => {
      if (--this.#fetching === 0 && this.#engine && engine.map_is_idle(this.#engine)) this.#idle();
    });
  }

  async #fetchDocuments(urls: string[]): Promise<void> {
    tilejson ??= await import("./tilejson-merge.js");
    await Promise.all(urls.map(async (url) => {
      if (url.startsWith(GEOTIFF)) {
        const { geotiffDocument } = await import("./geotiff-source.js");
        this.#tilejson.set(url, await geotiffDocument(url.slice(GEOTIFF.length), (u) => this.#transform?.(u, "Source")));
        return;
      }
      const archive = pmtilesArchive(url);
      if (archive !== null) {
        const { pmtilesDocument } = await import("./pmtiles.js");
        this.#tilejson.set(url, await pmtilesDocument(archive));
        return;
      }
      const res = await this.#fetch(url, "Source");
      if (!res.ok) throw new Error(`mbmap: TileJSON ${url}: HTTP ${res.status}`);
      this.#tilejson.set(url, await res.json());
    }));
  }

  /** `load` (the first time) and `idle`, unless a source's TileJSON or PMTiles header is still coming. */
  #idle(): void {
    if (this.#fetching > 0) return;
    if (!this.#loaded) {
      this.#loaded = true;
      this.#events.emit("load");
    }
    this.#events.emit("idle");
  }

  /**
   * Sets a key of the global state that `global-state` expressions read (null takes the style's
   * default back), as MapLibre's: layers reading it are drawn again, their tiles loaded again.
   */
  setGlobalStateProperty(name: string, value: unknown): this {
    const defaults = (this.#style?.state ?? {}) as Record<string, { default?: unknown } | undefined>;
    const next = value === null ? (defaults[name]?.default ?? null) : value;
    if (JSON.stringify(next) === JSON.stringify(this.#globalState[name])) return this;
    this.#globalState = { ...this.#globalState, [name]: next };
    if (this.#style) this.#apply(this.#style);
    return this;
  }

  /** A copy of the global state: each key with its value. */
  getGlobalState(): Record<string, unknown> {
    return edit.copy(this.#globalState);
  }

  /** The style with its TileJSON sources completed and tile URLs made absolute, as the engine takes it. */
  #engineStyle(style: StyleSpecification): StyleSpecification {
    const s = edit.withState(legacy && edit.hasLegacy(style) ? legacy.convertStyle(style) : style, this.#globalState);
    const urls = tileJSONUrls(s, this.#base);
    // Without the merger no document has come yet: every `url` source is still loading.
    const merged = urls.size === 0 ? s : tilejson ? tilejson.withTileJSON(s, urls, this.#tilejson, resolveTemplate) : withoutSources(s, new Set(urls.keys()));
    return resolveTiles(merged, this.#base);
  }

  /** A copy of the style drawn, GeoJSON data included (null until it has loaded). */
  getStyle(): StyleSpecification | null {
    return edit.copy(this.#style && edit.withoutCustom(this.#style));
  }

  /** Fires `warning` (and logs it) when what the engine leaves out of `drawn` changed. */
  #warn(drawn: StyleSpecification): void {
    const flat = engine.map_warnings(this.#engine!);
    const key = flat.join("\n");
    if (key === this.#warned) return;
    this.#warned = key;
    if (flat.length === 0) return;
    const warnings = edit.styleWarnings(flat, drawn);
    console.warn(`mbmap: the style uses what is not drawn yet:\n${warnings.map((w) => `${w.path}: ${w.message}`).join("\n")}`);
    // After the constructor, which draws an object style at once, has returned.
    queueMicrotask(() => this.#events.warn(warnings));
  }

  /** Swaps in `next`, an edit of the current style; a style the engine refuses fires `error`. */
  #apply(next: StyleSpecification): void {
    if (!this.#engine) return;
    const [geojson, rest] = splitGeoJSON(this.#engineStyle(next));
    const refused = engine.map_set_style(this.#engine, JSON.stringify(rest), this.#options.strict ?? false);
    if (refused) {
      this.#fail(new Error(refused));
      return;
    }
    this.#warn(rest);
    const previous = this.#style;
    this.#style = next;
    this.#syncMedia(next);
    this.#images.loadSprite(next.sprite, this.#base);
    // Custom layers the new style lacks are gone, as MapLibre's `setStyle` removes them.
    for (const id of this.#custom?.ids() ?? []) if (!edit.getLayer(next, id)) this.#custom!.remove(id);
    for (const id of this.#loadGeoJSON(geojson)) engine.map_reload_source(this.#engine, id);
    this.#drawn = rest;
    this.#showAttribution();
    this.#events.emit("styledata");
    this.#sourceData(previous, next);
  }

  /** `sourcedata` for each source of `next` that `previous` lacks or had otherwise. */
  #sourceData(previous: StyleSpecification | null, next: StyleSpecification): void {
    for (const id of Object.keys(next.sources ?? {})) {
      if (previous?.sources?.[id] !== next.sources[id]) this.#events.sourceData(id);
    }
  }

  /** Runs `f` on the current style and draws what it gives; its errors fire `error`. */
  #edit(f: (style: StyleSpecification) => StyleSpecification): this {
    if (!this.#style) throw new Error("mbmap: the style has not loaded yet");
    let next: StyleSpecification;
    try {
      next = f(this.#style);
    } catch (err) {
      this.#fail(err);
      return this;
    }
    // Run again once the converter has loaded, on the style as it will be then.
    if (!legacy && edit.hasLegacy(next)) {
      loadLegacy().then(() => this.#edit(f), (err: unknown) => this.#fail(err));
      return this;
    }
    this.#apply(next);
    return this;
  }

  /** Adds a style layer, or a custom layer (MapLibre's `CustomLayerInterface`; its `onAdd` runs once `custom.js` has loaded). */
  addLayer(layer: LayerSpecification | CustomLayerInterface, beforeId?: string): this {
    if (layer?.type !== "custom") return this.#edit((s) => edit.addLayer(s, layer as LayerSpecification, beforeId));
    const custom = layer as CustomLayerInterface;
    this.#edit((s) => {
      const why = edit.invalidCustomLayer(custom);
      if (why) throw new Error(`mbmap: layers.${String(custom.id)}: ${why}`);
      return edit.addLayer(s, { id: custom.id, type: "custom" }, beforeId);
    });
    // Only while the style still has it: an error or a later removeLayer leaves it out.
    this.#withCustom((c) => this.#style && edit.getLayer(this.#style, custom.id)?.type === "custom" && !c.get(custom.id) && c.add(custom));
    return this;
  }

  /** Draws a frame soon (a custom layer's animation asks for each of its frames). */
  triggerRepaint(): this {
    return this.#withEngine((m) => engine.map_trigger_repaint(m));
  }

  /** Runs `f` on the custom layers, loading `custom.js` and handing its renderer to the engine the first time. */
  #withCustom(f: (c: CustomLayers) => void): void {
    if (this.#custom) return f(this.#custom);
    this.#customLoading ??= import("./custom.js").then(({ CustomLayers }) => {
      const m = this.#engine;
      if (!m || this.#removed) return;
      this.#custom = new CustomLayers(this, engine.map_gl(m));
      engine.map_set_custom_renderer(m, this.#custom.draw);
    });
    this.#customLoading.then(
      () => this.#custom && f(this.#custom),
      (err: unknown) => this.#fail(err),
    );
  }

  removeLayer(id: string): this {
    return this.#edit((s) => edit.removeLayer(s, id));
  }

  /** Moves layer `id` before `beforeId`, or on top. */
  moveLayer(id: string, beforeId?: string): this {
    return this.#edit((s) => edit.moveLayer(s, id, beforeId));
  }

  /** Layer `id` as the style gives it, or a custom layer itself. */
  getLayer(id: string): LayerSpecification | CustomLayerInterface | undefined {
    const custom = this.#custom?.get(id);
    if (custom) return custom;
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

  /** Adds a source; one given by `url` (TileJSON) draws once its document has come. */
  addSource(id: string, source: unknown): this {
    this.#keepCanvases({ [id]: source });
    this.#edit((s) => edit.addSource(s, id, source));
    const missing = this.#missingTileJSON({ version: 8, sources: { [id]: source }, layers: [] }, this.#base);
    if (missing.length > 0) {
      this.#fetchTileJSON(missing, () => this.#style && this.#apply(this.#style)).catch((err: unknown) => this.#fail(err));
    }
    return this;
  }

  /** Removes source `id`; fires `error` while a layer or the terrain uses it. */
  removeSource(id: string): this {
    return this.#edit((s) => edit.removeSource(s, id));
  }

  /** Source `id`; a GeoJSON one has `setData` to replace its data (an object or a URL) and the cluster queries. */
  getSource(id: string): Source | undefined {
    const s = (this.#style && edit.sourceOf(this.#style, id)) as { type?: unknown; promoteId?: unknown } | undefined;
    if (!s || typeof s.type !== "string") return undefined;
    const source: Source = { id, type: s.type };
    if ("promoteId" in s) source.promoteId = edit.copy(s.promoteId);
    if (s.type === "geojson") {
      const ask =
        (op: ClusterQuery["op"]) =>
        (cluster: number, limit?: number, offset?: number): Promise<never> =>
          (this.#geojsonLoading ?? Promise.resolve(null)).then((t) => {
            if (!t) throw new Error("mbmap: GeoJSON sources did not load");
            return t.cluster(id, { op, cluster, limit, offset } as ClusterQuery) as Promise<never>;
          });
      Object.assign(source, {
        setData: (data: unknown) => void this.#edit((st) => edit.setSourceData(st, id, data)),
        getData: (): Promise<unknown> => {
          const data = (this.#style && (edit.sourceOf(this.#style, id) as { data?: unknown } | undefined))?.data;
          if (typeof data !== "string") return Promise.resolve(edit.copy(data));
          return this.#fetch(httpUrl(data, this.#base, `GeoJSON source ${id}: data`), "Source").then((res) => {
            if (!res.ok) throw new Error(`mbmap: GeoJSON source ${id}: HTTP ${res.status}`);
            return res.json();
          });
        },
        getClusterExpansionZoom: ask("expansion"),
        getClusterChildren: ask("children"),
        getClusterLeaves: ask("leaves"),
      });
    }
    if (s.type === "image" || s.type === "video" || s.type === "canvas") {
      const media = (f: (m: Media) => void) => () => {
        this.#withMedia(f);
        return source;
      };
      // The style keeps what MapLibre's `serialize` gives.
      const keep = (key: string, value: unknown) => {
        const now = this.#style && edit.sourceOf(this.#style, id);
        if (now) edit.setOwn(this.#style!.sources, id, { ...now, [key]: value });
      };
      Object.assign(source, {
        setCoordinates: (c: number[][]) => {
          keep("coordinates", edit.copy(c));
          return media((m) => m.setCoordinates(id, c))();
        },
        updateImage: (o: UpdateImageOptions) => {
          if (o.url !== undefined) keep("url", o.url);
          if (o.coordinates) keep("coordinates", edit.copy(o.coordinates));
          return media((m) => m.updateImage(id, o))();
        },
        play: media((m) => m.play(id)),
        pause: media((m) => m.pause(id)),
        getVideo: () => this.#media?.video(id),
        getCanvas: () => this.#media?.canvas(id),
      });
    }
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
          this.#geojson = createGeoJSONTiles(
            this.#geojsonSources,
            this.#base,
            (e) => this.#fail(e),
            { workerUrl: o.geojsonWorkerUrl, wasmUrl: o.geojsonWasmUrl, propertiesWasmUrl: o.geojsonPropertiesWasmUrl },
            (json) => engine.compile_cluster_properties(json),
            (url) => this.#transform?.(url, "Source"),
          );
          return this.#geojson;
        },
        (err: unknown) => {
          this.#fail(err);
          return null;
        },
      );
    }
    return [];
  }

  /** A GeoJSON tile for the engine, once the GeoJSON worker has started, or a GeoTIFF source's tile. */
  #providedTile(source: string, z: number, x: number, y: number): Promise<ArrayBuffer | null> {
    const spec = this.#style && (edit.sourceOf(this.#style, source) as Record<string, unknown> | undefined);
    if (spec?.type === "geotiff" && typeof spec.url === "string") {
      const url = httpUrl(spec.url, this.#base, `source "${source}": url`);
      const info = this.#tilejson.get(GEOTIFF + url) as Parameters<typeof import("./geotiff-source.js").geotiffTile>[2] | undefined;
      if (!info) return Promise.resolve(null);
      return import("./geotiff-source.js").then((m) => m.geotiffTile(url, spec, info, z, x, y, (u) => this.#transform?.(u, "Tile")));
    }
    if (this.#geojson) return this.#geojson.tile(source, z, x, y);
    return this.#geojsonLoading?.then((t) => t?.tile(source, z, x, y) ?? null) ?? Promise.resolve(null);
  }

  #create(style: StyleSpecification): void {
    const [geojson, resolved] = splitGeoJSON(this.#engineStyle(style));
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
      (source, z, x, y) => this.#providedTile(source, z, x, y),
      o.fontFamily ?? "sans-serif",
      limitsArray(this.#limits),
      o.strict ?? false,
    );
    this.#engine = map;
    this.#warn(resolved);
    this.#style = style;
    if (this.#transform) engine.map_set_transform_request(map, this.#transform);
    const canvas = this.#canvas;
    for (const type of ["mousedown", "mouseup", "mouseover", "mouseout", "mousemove", "click", "dblclick", "contextmenu"] as const) {
      canvas.addEventListener(
        type,
        (e) => {
          const r = canvas.getBoundingClientRect();
          this.#events.mouse(type, e, { x: e.clientX - r.left - canvas.clientLeft, y: e.clientY - r.top - canvas.clientTop });
        },
        { signal: this.#dom.signal },
      );
    }
    this.#loadGeoJSON(geojson);
    this.#syncMedia(style);
    HANDLERS.forEach((h, i) => engine.map_set_handler(map, i, this.#enabled[h]));
    engine.map_on_move_start(map, (e) => this.#moveStart(e));
    engine.map_on_move(map, () => this.#move(engine.map_input_event(map)));
    engine.map_on_move_end(map, (e) => this.#moveEnd(e));
    engine.map_on_render(map, () => {
      this.#locate(this.#tracked);
      this.#events.emit("render");
    });
    engine.map_on_idle(map, () => this.#idle());
    engine.map_on_missing_image(map, (id) => this.#events.emit("styleimagemissing", undefined, null, id));
    this.#images.loadSprite(style.sprite, this.#base);
    this.#drawn = resolved;
    this.#showAttribution();
    this.#events.emit("styledata");
    this.#sourceData(null, style);
    if (o.bounds) this.fitBounds(o.bounds, { ...o.fitBoundsOptions, duration: 0 });
    for (const f of this.#callsBeforeStart.splice(0)) f();
  }

  #setHandler(name: HandlerName, on: boolean): void {
    this.#enabled[name] = on;
    if (this.#engine) engine.map_set_handler(this.#engine, HANDLERS.indexOf(name), on);
  }

  #moveStart(e: Event | null): void {
    this.#last = this.#current();
    this.#events.emit("movestart", undefined, e);
  }

  #move(e: Event | null): void {
    const c = this.#current();
    const last = this.#last ?? c;
    const changed = (["zoom", "rotate", "pitch"] as const).filter((k, i) => [c.zoom !== last.zoom, c.bearing !== last.bearing, c.pitch !== last.pitch][i]);
    // As MapLibre: starts, then `move`, then what changed.
    for (const kind of changed) {
      if (!this.#changing[kind]) {
        this.#changing[kind] = true;
        this.#events.emit(`${kind}start`, undefined, e);
      }
    }
    if (changed.includes("zoom")) this.#showAttribution();
    this.#events.emit("move", undefined, e);
    for (const kind of changed) this.#events.emit(kind, undefined, e);
    this.#last = c;
  }

  #moveEnd(e: Event | null): void {
    for (const kind of ["zoom", "rotate", "pitch"] as const) {
      if (this.#changing[kind]) {
        this.#changing[kind] = false;
        this.#events.emit(`${kind}end`, undefined, e);
      }
    }
    this.#last = null;
    this.#events.emit("moveend", undefined, e);
  }

  /**
   * Layer `id`'s paint as drawn now (at this zoom) for a feature with `properties`: colors as straight
   * RGBA in 0 to 1 with the layer's opacity applied, sizes in CSS pixels; null for an unknown layer or
   * before the map has started. Legends read it.
   */
  evaluatePaint(id: string, properties: Record<string, unknown> = {}): PaintValues | null {
    return this.#engine ? engine.map_paint_at(this.#engine, id, properties) : null;
  }

  /** The attributions MapLibre's AttributionControl would show now: of the sources the layers shown or the terrain use. */
  getAttributions(): string[] {
    return [...this.#attributions];
  }

  /** Shows the attributions if they changed (the style, or a layer's zoom range at this zoom). */
  #showAttribution(): void {
    const texts = this.#drawn ? attributionsOf(this.#drawn, this.getZoom()) : [];
    if (texts.join("\n") === this.#attributions.join("\n") && this.#attribution) return;
    this.#attributions = texts;
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

  #fail(err: unknown): void {
    if (this.#removed) return;
    const error = err instanceof Error ? err : new Error(String(err));
    if (!this.#events.has("error")) console.error(error);
    this.#events.emit("error", error);
  }

  /** Tells each of `tracked` where its place is now: one engine call for all of them. */
  #locate(tracked: Iterable<Tracked>): void {
    const list = [...tracked];
    if (!this.#engine || list.length === 0) return;
    const out = engine.map_locate(this.#engine, list.flatMap((t) => [t.lnglat.lng, t.lnglat.lat]));
    list.forEach((t, i) => {
      try {
        t.f({ x: out[3 * i], y: out[3 * i + 1], covered: out[3 * i + 2] === 1 });
      } catch (err) {
        queueMicrotask(() => {
          throw err;
        });
      }
    });
  }

  /** Listens for `type`; with layer ids, for mouse events on those layers' features (`e.features`). */
  on(type: MapEventType, listener: MapEventListener): this;
  on(type: MapMouseEventType, layers: string | string[], listener: MapEventListener): this;
  on(type: MapEventType, a: MapEventListener | string | string[], b?: MapEventListener): this {
    this.#events.on(type, a, b);
    return this;
  }

  off(type: MapEventType, listener: MapEventListener): this;
  off(type: MapMouseEventType, layers: string | string[], listener: MapEventListener): this;
  off(type: MapEventType, a: MapEventListener | string | string[], b?: MapEventListener): this {
    this.#events.off(type, a, b);
    return this;
  }

  /** Listens for the next `type` event (on `layers`' features, if given); without a listener, resolves with it. */
  once(type: MapEventType): Promise<MapEvent>;
  once(type: MapEventType, listener: MapEventListener): this;
  once(type: MapMouseEventType, layers: string | string[]): Promise<MapEvent>;
  once(type: MapMouseEventType, layers: string | string[], listener: MapEventListener): this;
  once(type: MapEventType, a?: MapEventListener | string | string[], b?: MapEventListener): this | Promise<MapEvent> {
    return this.#events.once(type, a, b) ?? this;
  }

  /** Features drawn under `points` (CSS pixels: a point, or a box's closed ring), in MapLibre's order. */
  #query(points: number[], layers: string[] | null, filter: unknown): Promise<MapGeoJSONFeature[]> {
    const map = this.#engine;
    const style = this.#style;
    if (!map || !style) return Promise.resolve([]);
    if (!legacy && edit.isLegacyFilter(filter)) return loadLegacy().then(() => this.#query(points, layers, filter));
    return new Promise((resolve, reject) => {
      const refused = engine.map_query_rendered(map, points, layers === null, layers ?? [], filterText(filter), (tiles) => {
        const specs = new globalThis.Map<string, LayerSpecification | undefined>();
        const out: MapGeoJSONFeature[] = [];
        for (const { layer, feature } of orderRendered(tiles, style.layers as LayerSpecification[])) {
          if (!specs.has(layer)) specs.set(layer, edit.copy(edit.getLayer(style, layer)));
          const spec = specs.get(layer);
          if (!spec) continue;
          const f = feature as MapGeoJSONFeature;
          f.layer = spec;
          f.source = spec.source ?? "";
          if (spec["source-layer"]) f.sourceLayer = spec["source-layer"];
          f.state = f.id === undefined ? {} : { ...this.#states.get(f.source)?.get(f.sourceLayer ?? "")?.get(String(f.id)) };
          out.push(f);
        }
        resolve(out);
      });
      if (refused) reject(new Error(refused));
    });
  }

  /**
   * The features drawn at a point or in a box (`[[x0, y0], [x1, y1]]`, CSS pixels; the whole map
   * when left out), topmost first, as MapLibre's `queryRenderedFeatures` finds them. A Promise:
   * the workers hold the geometry. Rejects on a filter mbmap cannot evaluate.
   */
  queryRenderedFeatures(geometryOrOptions?: PointLike | [PointLike, PointLike] | QueryRenderedFeaturesOptions, options?: QueryRenderedFeaturesOptions): Promise<MapGeoJSONFeature[]> {
    const { geometry, options: o } = queryArgs(geometryOrOptions, options);
    const layers = queryLayers(o.layers, (id) => !!this.getLayer(id));
    if (layers instanceof Error) {
      this.#fail(layers);
      return Promise.resolve([]);
    }
    return this.#query(queryPoints(geometry, this.#canvas.clientWidth, this.#canvas.clientHeight), layers, o.filter);
  }

  /** The source's state map for `sourceLayer`, made on first use. */
  #stateMap(source: string, sourceLayer: string): globalThis.Map<string, Record<string, unknown>> {
    let bySource = this.#states.get(source);
    if (!bySource) this.#states.set(source, (bySource = new globalThis.Map()));
    let byLayer = bySource.get(sourceLayer);
    if (!byLayer) bySource.set(sourceLayer, (byLayer = new globalThis.Map()));
    return byLayer;
  }

  /** The feature's source layer, checked as MapLibre does: required for vector sources. */
  #stateLayer(feature: FeatureIdentifier): string | null {
    const source = (this.#style && edit.sourceOf(this.#style, feature.source)) as { type?: unknown } | undefined;
    const layer = stateLayer(source, feature);
    if (layer instanceof Error) {
      this.#fail(layer);
      return null;
    }
    return layer;
  }

  #sendState(source: string, sourceLayer: string, id: string, state: Record<string, unknown> | null): void {
    this.#withEngine((m) => engine.map_set_feature_state(m, source, sourceLayer, id, state));
  }

  /**
   * Merges `state` into the feature's state (MapLibre's `setFeatureState`); paint that reads
   * `["feature-state", key]` draws the feature with it. The feature needs an id: the tile's,
   * the GeoJSON feature's, or the property the source's `promoteId` names.
   */
  setFeatureState(feature: FeatureIdentifier, state: Record<string, unknown>): this {
    const layer = this.#stateLayer(feature);
    if (layer === null) return this;
    const refused = stateIdError(feature);
    if (refused) {
      this.#fail(refused);
      return this;
    }
    const states = this.#stateMap(feature.source, layer);
    const id = String(feature.id);
    const next = { ...states.get(id), ...edit.copy(state) };
    states.set(id, next);
    this.#sendState(feature.source, layer, id, next);
    return this;
  }

  /** A copy of the feature's state (`{}` when it has none). */
  getFeatureState(feature: FeatureIdentifier): Record<string, unknown> {
    const layer = this.#stateLayer(feature);
    if (layer === null || feature.id === undefined) return {};
    return { ...this.#states.get(feature.source)?.get(layer)?.get(String(feature.id)) };
  }

  /**
   * Removes `key` from the feature's state, or its whole state; without an id, the states of
   * every feature of the source (layer), as MapLibre's `removeFeatureState`.
   */
  removeFeatureState(target: FeatureIdentifier, key?: string): this {
    const layer = this.#stateLayer(target);
    if (layer === null) return this;
    const refused = removeStateError(target, key);
    if (refused) {
      this.#fail(refused);
      return this;
    }
    const states = this.#stateMap(target.source, layer);
    const ids = target.id === undefined ? [...states.keys()] : [String(target.id)];
    for (const id of ids) {
      const old = states.get(id);
      if (!old) continue;
      if (key === undefined) {
        states.delete(id);
        this.#sendState(target.source, layer, id, null);
      } else {
        const { [key]: _, ...rest } = old;
        states.set(id, rest);
        this.#sendState(target.source, layer, id, rest);
      }
    }
    return this;
  }

  /** The features of a source in the tiles drawn (`sourceLayer` required for vector sources), as MapLibre's `querySourceFeatures`. */
  querySourceFeatures(sourceId: string, options: QuerySourceFeatureOptions = {}): Promise<GeoJSONFeature[]> {
    const map = this.#engine;
    if (!map) return Promise.resolve([]);
    if (!legacy && edit.isLegacyFilter(options.filter)) return loadLegacy().then(() => this.querySourceFeatures(sourceId, options));
    return new Promise((resolve, reject) => {
      const refused = engine.map_query_source(map, sourceId, options.sourceLayer ?? "", filterText(options.filter), (tiles) => resolve(tiles.flatMap((t) => t.hits.map((h) => h.feature))));
      if (refused) reject(new Error(refused));
    });
  }

  /**
   * An image of the current view: once its tiles, sprite and TileJSON have loaded, drawn at
   * `pixelRatio` offscreen (the canvas is left as it is) and encoded as `type`. Views larger than
   * the GPU draws at once are drawn in parts and joined. Rejects if the map is removed first.
   */
  async toBlob(options: ToBlobOptions = {}): Promise<Blob> {
    const ratio = options.pixelRatio ?? globalThis.devicePixelRatio ?? 1;
    if (!(ratio > 0 && Number.isFinite(ratio))) throw new Error(`mbmap: pixelRatio must be a positive number: ${ratio}`);
    const loading = import("./export.js");
    while (!this.#engine || !engine.map_is_idle(this.#engine) || this.#fetching > 0) {
      if (this.#removed) throw new Error("mbmap: the map was removed");
      await new Promise<void>((resolve) => {
        this.once("idle", () => resolve());
        this.#dom.signal.addEventListener("abort", () => resolve(), { once: true });
      });
    }
    const { encodeImage } = await loading;
    const map = this.#engine;
    if (!map) throw new Error("mbmap: the map was removed");
    const side = Math.max(1, Math.min(options.maxSize ?? Infinity, engine.map_max_region(map)));
    const region = (x: number, y: number, w: number, h: number) => engine.map_render_region(map, ratio, x, y, w, h);
    return encodeImage(Math.round(this.#canvas.clientWidth * ratio), Math.round(this.#canvas.clientHeight * ratio), side, region, options.type, options.quality);
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

  /**
   * Adds style image `id` for patterns and icons (MapLibre's `addImage`): ImageData, raw RGBA
   * (`{width, height, data}`), or an image, bitmap or canvas. An id already used fires `error`.
   */
  addImage(id: string, image: ImageInput, options: StyleImageOptions = {}): this {
    this.#images.set(id, image, options, false);
    return this;
  }

  /** Replaces the pixels of style image `id`. */
  updateImage(id: string, image: ImageInput): this {
    this.#images.set(id, image, {}, true);
    return this;
  }

  /** Whether style image `id` exists. */
  hasImage(id: string): boolean {
    return this.#images.has(id);
  }

  /** Removes style image `id`. */
  removeImage(id: string): this {
    this.#images.remove(id);
    return this;
  }

  /** The style images' names: the sprite's and those `addImage` added. */
  listImages(): string[] {
    return this.#images.list();
  }

  /** Fetches an image (through `transformRequest`) for `addImage` (MapLibre's `loadImage`). */
  loadImage(url: string): Promise<{ data: ImageBitmap }> {
    return this.#images.load(url, this.#base);
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

  /**
   * Follows `lnglat` on screen for an element drawn over the map: `callback` gets its position on
   * the terrain, and whether the terrain hides it, after every frame (and at once if the map has
   * started), as MapLibre's `Marker` places itself; one engine call per frame for all.
   */
  track(lnglat: LngLatLike, callback: (position: ScreenPosition) => void): Tracker {
    const t: Tracked = { lnglat: toLngLat(lnglat), f: callback };
    this.#tracked.add(t);
    this.#locate([t]);
    const map = this;
    return {
      getLngLat: () => ({ ...t.lnglat }),
      setLngLat(lnglat: LngLatLike) {
        t.lnglat = toLngLat(lnglat);
        if (map.#tracked.has(t)) map.#locate([t]);
        return this;
      },
      remove: () => {
        this.#tracked.delete(t);
      },
    };
  }

  /** The screen point (CSS pixels from the top-left corner) of `lnglat`, on the terrain if any. */
  project(lnglat: LngLatLike): { x: number; y: number } {
    const p = toLngLat(lnglat);
    if (!this.#engine) return { x: NaN, y: NaN };
    const [x, y] = engine.map_project(this.#engine, p.lng, p.lat);
    return { x, y };
  }

  /** The point under screen point `point`, on the terrain if any. */
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
    checkLimits(next);
    this.#limits = next;
    if (this.#engine) engine.map_set_limits(this.#engine, limitsArray(next));
    return this;
  }

  setMinZoom(zoom?: number | null): this {
    return this.#setLimits({ minZoom: zoom ?? MIN_ZOOM });
  }

  /** With `constrained`, the zoom the camera can go down to here (the latitude limits and `maxBounds` raise it). */
  getMinZoom(constrained = false): number {
    const min = this.#limits.minZoom;
    return constrained && this.#engine ? engine.map_constrained_zoom(this.#engine, min) : min;
  }

  setMaxZoom(zoom?: number | null): this {
    return this.#setLimits({ maxZoom: zoom ?? MAX_ZOOM });
  }

  getMaxZoom(): number {
    return this.#limits.maxZoom;
  }

  setMinPitch(pitch?: number | null): this {
    return this.#setLimits({ minPitch: pitch ?? MIN_PITCH });
  }

  getMinPitch(): number {
    return this.#limits.minPitch;
  }

  setMaxPitch(pitch?: number | null): this {
    return this.#setLimits({ maxPitch: pitch ?? MAX_PITCH });
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
    this.#dom.abort();
    if (this.#engine) engine.map_destroy(this.#engine);
    this.#engine = null;
    this.#geojson?.terminate();
    this.#geojson = null;
    this.#media?.destroy();
    this.#custom?.destroy();
    this.#events.clear();
    this.#images.close();
    this.#canvas.remove();
    this.#attribution?.remove();
  }
}
