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
import type { ClusterQuery, GeoJSONSource, GeoJSONTiles } from "./geojson";
import type { Media, UpdateImageOptions } from "./media";
import type { CustomLayerInterface, CustomLayers } from "./custom";
import { type GeoJSONFeature, orderRendered, queryPoints } from "./query";
import * as edit from "./style";
import type { LayerSpecification, StyleSpecification } from "./style";
import { attributionsOf } from "./attribution";
import { tileJSONUrls, withTileJSON } from "./tilejson";
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
import { httpUrl, resolveTemplate, wasmUrl, workerScriptUrl } from "./urls";
import { type ImageInput, type StyleImageOptions, canvasPixels, imageOptions, imagePixels } from "./images";

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

/** The largest image `toBlob` makes: what Chromium and Safari let a canvas hold. */
const MAX_IMAGE_SIDE = 32767;
const MAX_IMAGE_PIXELS = 16384 * 16384;

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

/** `legacy.js` once loaded; only styles with legacy filters or property functions load it. */
let legacy: typeof import("./legacy") | null = null;
let legacyLoading: Promise<unknown> | null = null;

function loadLegacy(): Promise<unknown> {
  legacyLoading ??= import("./legacy.js").then((m) => (legacy = m));
  return legacyLoading;
}

/** A query's filter as the engine takes it: JSON text (empty for none), legacy filters converted. */
function filterText(filter: unknown): string {
  if (filter === undefined) return "";
  return JSON.stringify(legacy && edit.isLegacyFilter(filter) ? legacy.convertFilter(filter) : filter);
}

/** The style's GeoJSON sources, and the style without their data (only their worker needs it). */
function splitGeoJSON(style: StyleSpecification): [GeoJSONSource[], StyleSpecification] {
  const found: GeoJSONSource[] = [];
  const sources = Object.fromEntries(
    Object.entries(style.sources ?? {}).map(([id, s]) => {
      const spec = s as Record<string, unknown>;
      if (spec?.type !== "geojson") return [id, s];
      found.push({ id, spec });
      return [id, { ...spec, data: null }];
    }),
  );
  return [found, { ...style, sources }];
}

export class Map {
  #container: HTMLElement;
  #canvas: HTMLCanvasElement;
  #attribution: HTMLElement | null = null;
  #attributions: string[] = [];
  /** The style as the engine draws it (TileJSON merged), whose sources the attributions come from. */
  #drawn: StyleSpecification | null = null;
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
  #base = new URL(document.baseURI);
  #styleRequest = 0;
  #tilejson = new globalThis.Map<string, unknown>();
  #transform: RequestTransformFunction | null = null;
  #camera: Camera;
  #listeners = new globalThis.Map<MapEventType, Set<MapEventListener>>();
  #tracked = new Set<Tracked>();
  #loaded = false;
  #fetching = 0;
  /** The style images' names (the sprite's and those `addImage` added), and which came from the sprite. */
  #images = new Set<string>();
  #spriteImages: string[] = [];
  #spriteKey = "null";
  #removed = false;
  #options: MapOptions;
  #limits: Limits;
  #enabled: Record<HandlerName, boolean>;
  #callsBeforeStart: (() => void)[] = [];
  #changing = { zoom: false, rotate: false, pitch: false };
  #layerListeners: { type: MapMouseEventType; layers: string[]; listener: MapEventListener; inside: boolean }[] = [];
  #mouseDown: { x: number; y: number } | null = null;
  #hovering = false;
  #nextHover: { e: MouseEvent; p: { x: number; y: number } } | null = null;
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
          this.#fail(err instanceof Error ? err : new Error(String(err)));
          return;
        }
      }
      const next = edit.keepGeoJSONData(this.#style, edit.copy(swapped));
      if (!legacy && edit.hasLegacy(next)) {
        loadLegacy().then(() => use(s, base), (err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err))));
        return;
      }
      this.#base = base;
      if (this.#engine) this.#apply(next);
      else this.#create(next);
    };
    // Sources given by TileJSON wait for their documents.
    const ready = (s: StyleSpecification, base: URL) => {
      const missing = this.#missingTileJSON(s, base);
      if (missing.length === 0) return use(s, base);
      this.#fetchTileJSON(missing)
        .then(() => use(s, base))
        .catch((err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err))));
    };
    if (typeof style === "string") {
      const url = new URL(httpUrl(style, document.baseURI, "the style"));
      this.#fetch(url.href, "Style")
        .then((res) => {
          if (!res.ok) throw new Error(`mbmap: style: HTTP ${res.status}`);
          return res.json() as Promise<StyleSpecification>;
        })
        .then((s) => ready(s, url))
        .catch((err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err))));
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
    this.#mediaLoading ??=import("./media.js").then(({ Media }) => {
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
      (err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err))),
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

  /** Fetches TileJSON documents (without credentials), or PMTiles headers, into the cache. */
  async #fetchTileJSON(urls: string[]): Promise<void> {
    this.#fetching++;
    try {
      await this.#fetchDocuments(urls);
    } finally {
      // `idle` waited for these sources; it comes now if the engine is idle without them.
      if (--this.#fetching === 0 && this.#engine && engine.map_is_idle(this.#engine)) this.#idle();
    }
  }

  async #fetchDocuments(urls: string[]): Promise<void> {
    await Promise.all(urls.map(async (url) => {
      if (url.startsWith("pmtiles://")) {
        const { pmtilesDocument } = await import("./pmtiles.js");
        this.#tilejson.set(url, await pmtilesDocument(url.slice(10)));
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
      this.#emit("load");
    }
    this.#emit("idle");
  }

  /** The style with its TileJSON sources completed and tile URLs made absolute, as the engine takes it. */
  #engineStyle(style: StyleSpecification): StyleSpecification {
    const s = legacy && edit.hasLegacy(style) ? legacy.convertStyle(style) : style;
    return resolveTiles(withTileJSON(s, this.#base, this.#tilejson, resolveTemplate), this.#base);
  }

  /** A copy of the style drawn, GeoJSON data included (null until it has loaded). */
  getStyle(): StyleSpecification | null {
    return edit.copy(this.#style && edit.withoutCustom(this.#style));
  }

  /** Swaps in `next`, an edit of the current style; a style the engine refuses fires `error`. */
  #apply(next: StyleSpecification): void {
    if (!this.#engine) return;
    const [geojson, rest] = splitGeoJSON(this.#engineStyle(next));
    const refused = engine.map_set_style(this.#engine, JSON.stringify(rest));
    if (refused) {
      this.#fail(new Error(refused));
      return;
    }
    this.#style = next;
    this.#syncMedia(next);
    this.#loadSprite(next.sprite);
    // Custom layers the new style lacks are gone, as MapLibre's `setStyle` removes them.
    for (const id of this.#custom?.ids() ?? []) if (!edit.getLayer(next, id)) this.#custom!.remove(id);
    for (const id of this.#loadGeoJSON(geojson)) engine.map_reload_source(this.#engine, id);
    this.#drawn = rest;
    this.#showAttribution();
    this.#emit("styledata");
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
    // Run again once the converter has loaded, on the style as it will be then.
    if (!legacy && edit.hasLegacy(next)) {
      loadLegacy().then(() => this.#edit(f), (err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err))));
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
      (err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err))),
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
      this.#fetchTileJSON(missing)
        .then(() => this.#style && this.#apply(this.#style))
        .catch((err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err))));
    }
    return this;
  }

  /** Removes source `id`; fires `error` while a layer or the terrain uses it. */
  removeSource(id: string): this {
    return this.#edit((s) => edit.removeSource(s, id));
  }

  /** Source `id`; a GeoJSON one has `setData` to replace its data (an object or a URL) and the cluster queries. */
  getSource(id: string): Source | undefined {
    const s = this.#style?.sources[id] as { type?: unknown } | undefined;
    if (!s || typeof s.type !== "string") return undefined;
    const source: Source = { id, type: s.type };
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
        const now = this.#style?.sources[id];
        if (now) this.#style!.sources[id] = { ...now, [key]: value };
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
      (source, z, x, y) => this.#geojsonTile(source, z, x, y),
      o.fontFamily ?? "sans-serif",
      limitsArray(this.#limits),
    );
    this.#engine = map;
    this.#style = style;
    if (this.#transform) engine.map_set_transform_request(map, this.#transform);
    const canvas = this.#canvas;
    for (const type of ["mousedown", "mouseup", "mouseover", "mouseout", "mousemove", "click", "dblclick", "contextmenu"] as const) {
      canvas.addEventListener(
        type,
        (e) => {
          const r = canvas.getBoundingClientRect();
          this.#mouse(type, e, { x: e.clientX - r.left - canvas.clientLeft, y: e.clientY - r.top - canvas.clientTop });
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
      this.#emit("render");
    });
    engine.map_on_idle(map, () => this.#idle());
    engine.map_on_missing_image(map, (id) => this.#emitMissing(id));
    this.#loadSprite(style.sprite);
    this.#drawn = resolved;
    this.#showAttribution();
    this.#emit("styledata");
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
    if (changed.includes("zoom")) this.#showAttribution();
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

  #fail(error: Error): void {
    if (this.#removed) return;
    if (!this.#listeners.get("error")?.size) console.error(error);
    this.#emit("error", error);
  }

  #emit(type: MapEventType, error?: Error, originalEvent?: Event | null): void {
    const event: MapEvent = { type, target: this };
    if (error) event.error = error;
    if (originalEvent) event.originalEvent = originalEvent;
    this.#fire(event, this.#listeners.get(type) ?? []);
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

  #fire(event: MapEvent, listeners: Iterable<MapEventListener>): void {
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

  #mouseEvent(type: MapMouseEventType, e: MouseEvent, p: { x: number; y: number }, features?: MapGeoJSONFeature[]): MapEvent {
    const event: MapEvent = { type, target: this, originalEvent: e, point: p, lngLat: this.unproject(p) };
    if (features) event.features = features;
    return event;
  }

  /**
   * A DOM mouse event on the canvas: the map's own (a click only after less than 3 px of movement),
   * then the layers' listeners once a query finds their features (`mouseenter` and `mouseleave`
   * follow `mousemove` and `mouseout`), as in MapLibre.
   */
  #mouse(type: Exclude<MapMouseEventType, "mouseenter" | "mouseleave">, e: MouseEvent, p: { x: number; y: number }): void {
    if (type === "mousedown") this.#mouseDown = p;
    if (type === "click" && this.#mouseDown && Math.hypot(p.x - this.#mouseDown.x, p.y - this.#mouseDown.y) >= 3) return;
    this.#fire(this.#mouseEvent(type, e, p), this.#listeners.get(type) ?? []);
    const hover = (l: { type: MapMouseEventType }) => l.type === "mouseenter" || l.type === "mouseleave";
    if (type === "mouseout") {
      for (const l of this.#layerListeners) {
        if (!hover(l) || !l.inside) continue;
        l.inside = false;
        if (l.type === "mouseleave") this.#fire(this.#mouseEvent("mouseleave", e, p), [l.listener]);
      }
    }
    const asked = this.#layerListeners.filter((l) => l.type === type || (type === "mousemove" && hover(l)));
    if (asked.length === 0) return;
    if (type === "mousemove") {
      // One query at a time; moves in between keep only the latest.
      if (this.#hovering) {
        this.#nextHover = { e, p };
        return;
      }
      this.#hovering = true;
    }
    const layers = [...new Set(asked.flatMap((l) => l.layers))].filter((id) => this.getLayer(id));
    const found = layers.length === 0 ? Promise.resolve([]) : this.#query([p.x, p.y], layers, undefined);
    found
      .catch(() => [] as MapGeoJSONFeature[])
      .then((features) => {
        for (const l of asked) {
          const mine = features.filter((f) => l.layers.includes(f.layer.id));
          if (l.type === type) {
            if (mine.length > 0) this.#fire(this.#mouseEvent(type, e, p, mine), [l.listener]);
          } else if (mine.length > 0 && !l.inside) {
            l.inside = true;
            if (l.type === "mouseenter") this.#fire(this.#mouseEvent("mouseenter", e, p, mine), [l.listener]);
          } else if (mine.length === 0 && l.inside) {
            l.inside = false;
            if (l.type === "mouseleave") this.#fire(this.#mouseEvent("mouseleave", e, p), [l.listener]);
          }
        }
        if (type !== "mousemove") return;
        this.#hovering = false;
        const next = this.#nextHover;
        this.#nextHover = null;
        if (next && !this.#removed) this.#mouse("mousemove", next.e, next.p);
      });
  }

  /** Listens for `type`; with layer ids, for mouse events on those layers' features (`e.features`). */
  on(type: MapEventType, listener: MapEventListener): this;
  on(type: MapMouseEventType, layers: string | string[], listener: MapEventListener): this;
  on(type: MapEventType, a: MapEventListener | string | string[], b?: MapEventListener): this {
    if (typeof a === "function") {
      let set = this.#listeners.get(type);
      if (!set) this.#listeners.set(type, (set = new Set()));
      set.add(a);
    } else if (b) {
      this.#layerListeners.push({ type: type as MapMouseEventType, layers: Array.isArray(a) ? [...a] : [a], listener: b, inside: false });
    }
    return this;
  }

  off(type: MapEventType, listener: MapEventListener): this;
  off(type: MapMouseEventType, layers: string | string[], listener: MapEventListener): this;
  off(type: MapEventType, a: MapEventListener | string | string[], b?: MapEventListener): this {
    if (typeof a === "function") {
      this.#listeners.get(type)?.delete(a);
    } else {
      const ids = Array.isArray(a) ? a : [a];
      const same = (l: { type: string; layers: string[]; listener: MapEventListener }) =>
        l.type === type && l.listener === b && l.layers.length === ids.length && l.layers.every((id, i) => id === ids[i]);
      this.#layerListeners = this.#layerListeners.filter((l) => !same(l));
    }
    return this;
  }

  /** Listens for the next `type` event (on `layers`' features, if given); without a listener, resolves with it. */
  once(type: MapEventType): Promise<MapEvent>;
  once(type: MapEventType, listener: MapEventListener): this;
  once(type: MapMouseEventType, layers: string | string[]): Promise<MapEvent>;
  once(type: MapMouseEventType, layers: string | string[], listener: MapEventListener): this;
  once(type: MapEventType, a?: MapEventListener | string | string[], b?: MapEventListener): this | Promise<MapEvent> {
    if (a === undefined || typeof a === "function") {
      if (!a) return new Promise((resolve) => this.once(type, resolve));
      const listener = a;
      const wrapped: MapEventListener = (e) => {
        this.off(type, wrapped);
        listener(e);
      };
      return this.on(type, wrapped);
    }
    const layers = a;
    if (!b) return new Promise((resolve) => this.once(type as MapMouseEventType, layers, resolve));
    const listener = b;
    const wrapped: MapEventListener = (e) => {
      this.off(type as MapMouseEventType, layers, wrapped);
      listener(e);
    };
    return this.on(type as MapMouseEventType, layers, wrapped);
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
    const isPoint = (g: unknown) => (Array.isArray(g) ? typeof g[0] === "number" : typeof (g as { x?: unknown })?.x === "number");
    let o = options ?? {};
    let geometry: [number, number] | [[number, number], [number, number]] | null = null;
    if (geometryOrOptions !== undefined && (Array.isArray(geometryOrOptions) || isPoint(geometryOrOptions))) {
      const pair = (q: PointLike): [number, number] => {
        const p = toPoint(q);
        return [p.x, p.y];
      };
      geometry = isPoint(geometryOrOptions)
        ? pair(geometryOrOptions as PointLike)
        : [pair((geometryOrOptions as [PointLike, PointLike])[0]), pair((geometryOrOptions as [PointLike, PointLike])[1])];
    } else if (geometryOrOptions !== undefined) {
      o = geometryOrOptions as QueryRenderedFeaturesOptions;
    }
    let layers: string[] | null = null;
    if (o.layers !== undefined) {
      if (!Array.isArray(o.layers) && !(o.layers instanceof Set)) {
        this.#fail(new Error("mbmap: layers must be an Array or a Set of strings"));
        return Promise.resolve([]);
      }
      layers = [...o.layers];
      const missing = layers.find((id) => !this.getLayer(id));
      if (missing !== undefined) {
        this.#fail(new Error(`mbmap: the layer '${missing}' does not exist in the map's style and cannot be queried for features`));
        return Promise.resolve([]);
      }
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
    const source = this.#style?.sources[feature.source] as { type?: unknown } | undefined;
    if (!source) {
      this.#fail(new Error(`mbmap: the source '${feature.source}' does not exist in the map's style`));
      return null;
    }
    if (source.type === "vector" && !feature.sourceLayer) {
      this.#fail(new Error("mbmap: the sourceLayer parameter must be provided for vector source types"));
      return null;
    }
    return source.type === "vector" ? (feature.sourceLayer as string) : "";
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
    if (feature.id === undefined || feature.id === null || feature.id === "") {
      this.#fail(new Error("mbmap: the feature id parameter must be provided and non-empty"));
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
    if (target.id === undefined && key !== undefined) {
      this.#fail(new Error("mbmap: a feature id is required to remove its specific state property"));
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
   * An image of the current view: once its tiles have loaded, drawn at `pixelRatio` offscreen (the
   * canvas is left as it is) and encoded as `type`. Views larger than the GPU draws at once are
   * drawn in parts and joined.
   */
  async toBlob(options: ToBlobOptions = {}): Promise<Blob> {
    const ratio = options.pixelRatio ?? globalThis.devicePixelRatio ?? 1;
    if (!(ratio > 0 && Number.isFinite(ratio))) throw new Error(`mbmap: pixelRatio must be a positive number: ${ratio}`);
    while (!this.#engine || !engine.map_is_idle(this.#engine)) {
      if (this.#removed) throw new Error("mbmap: the map was removed");
      await this.once("idle");
    }
    const map = this.#engine;
    const width = Math.round(this.#canvas.clientWidth * ratio);
    const height = Math.round(this.#canvas.clientHeight * ratio);
    if (width < 1 || height < 1 || width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE || width * height > MAX_IMAGE_PIXELS) {
      throw new Error(`mbmap: cannot make a ${width} x ${height} image`);
    }
    const side = Math.max(1, Math.min(options.maxSize ?? Infinity, engine.map_max_region(map)));
    const out = document.createElement("canvas");
    out.width = width;
    out.height = height;
    const ctx = out.getContext("2d");
    if (!ctx) throw new Error("mbmap: no 2D canvas for the image");
    for (let y = 0; y < height; y += side) {
      for (let x = 0; x < width; x += side) {
        const w = Math.min(side, width - x);
        const h = Math.min(side, height - y);
        ctx.putImageData(new ImageData(engine.map_render_region(map, ratio, x, y, w, h), w, h), x, y);
      }
    }
    return new Promise((resolve, reject) => {
      out.toBlob((blob) => (blob ? resolve(blob) : reject(new Error("mbmap: the image could not be encoded"))), options.type, options.quality);
    });
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

  /** Loads the images of `sprite` when it changes, replacing the previous sprite's; `idle` waits for them. */
  #loadSprite(sprite: unknown): void {
    const key = JSON.stringify(sprite ?? null);
    if (key === this.#spriteKey) return;
    this.#spriteKey = key;
    for (const name of this.#spriteImages.splice(0)) this.removeImage(name);
    // Tiles with icons wait for the sprite, as MapLibre's do.
    this.#withEngine((m) => engine.map_hold_images(m, sprite != null));
    if (sprite == null) return;
    this.#fetching++;
    import("./sprite.js")
      .then((m) => m.loadSprites(sprite, globalThis.devicePixelRatio ?? 1, this.#base, (url, type) => this.#fetch(url, type)))
      .then((images) => {
        if (key !== this.#spriteKey || this.#removed) return;
        for (const { name, pixels, pixelRatio, sdf } of images) {
          if (this.#images.has(name)) continue;
          this.#images.add(name);
          this.#spriteImages.push(name);
          this.#withEngine((m) => engine.map_add_image(m, name, pixels.width, pixels.height, pixels.data, pixelRatio, sdf));
        }
      })
      .catch((err: unknown) => this.#fail(err instanceof Error ? err : new Error(String(err))))
      .finally(() => {
        if (key === this.#spriteKey) this.#withEngine((m) => engine.map_hold_images(m, false));
        if (--this.#fetching === 0 && this.#engine && engine.map_is_idle(this.#engine)) this.#idle();
      });
  }

  #emitMissing(id: string): void {
    const event: MapEvent = { type: "styleimagemissing", target: this, id };
    this.#fire(event, this.#listeners.get("styleimagemissing") ?? []);
  }

  /**
   * Adds style image `id` for patterns and icons (MapLibre's `addImage`): ImageData, raw RGBA
   * (`{width, height, data}`), or an image, bitmap or canvas. An id already used fires `error`.
   */
  addImage(id: string, image: ImageInput, options: StyleImageOptions = {}): this {
    if (this.#images.has(id)) {
      this.#fail(new Error(`mbmap: an image named "${id}" already exists`));
      return this;
    }
    return this.#setImage(id, image, options);
  }

  /** Replaces the pixels of style image `id`. */
  updateImage(id: string, image: ImageInput): this {
    if (!this.#images.has(id)) {
      this.#fail(new Error(`mbmap: no image named "${id}"`));
      return this;
    }
    return this.#setImage(id, image, {});
  }

  #setImage(id: string, image: ImageInput, options: StyleImageOptions): this {
    let pixels, opts;
    try {
      pixels = imagePixels(image, canvasPixels);
      opts = imageOptions(options);
    } catch (err) {
      this.#fail(err instanceof Error ? err : new Error(String(err)));
      return this;
    }
    this.#images.add(id);
    return this.#withEngine((m) => engine.map_add_image(m, id, pixels.width, pixels.height, pixels.data, opts.pixelRatio, opts.sdf));
  }

  /** Whether style image `id` exists. */
  hasImage(id: string): boolean {
    return this.#images.has(id);
  }

  /** Removes style image `id`. */
  removeImage(id: string): this {
    if (!this.#images.delete(id)) return this;
    return this.#withEngine((m) => engine.map_remove_image(m, id));
  }

  /** The style images' names. */
  listImages(): string[] {
    return [...this.#images];
  }

  /** Fetches an image (through `transformRequest`) for `addImage` (MapLibre's `loadImage`). */
  async loadImage(url: string): Promise<{ data: ImageBitmap }> {
    const res = await this.#fetch(httpUrl(url, this.#base, "an image"), "Image");
    if (!res.ok) throw new Error(`mbmap: image ${url}: HTTP ${res.status}`);
    return { data: await createImageBitmap(await res.blob(), { premultiplyAlpha: "none", colorSpaceConversion: "none" }) };
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

  /** With `constrained`, the zoom the camera can go down to here (the latitude limits and `maxBounds` raise it). */
  getMinZoom(constrained = false): number {
    const min = this.#limits.minZoom;
    return constrained && this.#engine ? engine.map_constrained_zoom(this.#engine, min) : min;
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
    this.#dom.abort();
    if (this.#engine) engine.map_destroy(this.#engine);
    this.#engine = null;
    this.#geojson?.terminate();
    this.#geojson = null;
    this.#media?.destroy();
    this.#custom?.destroy();
    this.#listeners.clear();
    this.#layerListeners = [];
    this.#canvas.remove();
    this.#attribution?.remove();
  }
}
