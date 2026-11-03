// The facade's public types (VISION §6), apart from the `Map` that uses them.
import type { FitBoundsOptions, LngLat, LngLatBoundsLike, LngLatLike } from "./camera";
import type { Map } from "./index";
import type { GeoJSONFeature } from "./query";
import type { LayerSpecification, StyleSpecification } from "./style";

/** A rendered feature: the style layer that drew it (as in the style), its source, source layer and state. */
export interface MapGeoJSONFeature extends GeoJSONFeature {
  layer: LayerSpecification;
  source: string;
  sourceLayer?: string;
  state: Record<string, unknown>;
}

/** A feature whose state is set: its source, its source layer (vector sources only) and its id (MapLibre's `FeatureIdentifier`). */
export interface FeatureIdentifier {
  source: string;
  sourceLayer?: string;
  id?: number | string;
}

/** `layers` to look in (all by default) and a `filter` the features must pass, as in MapLibre. */
export interface QueryRenderedFeaturesOptions {
  layers?: string[] | Set<string>;
  filter?: unknown;
}

/** The source layer to read (required for vector sources) and a `filter`, as in MapLibre. */
export interface QuerySourceFeatureOptions {
  sourceLayer?: string;
  filter?: unknown;
}

/** What a `transformRequest` is asked about: the style, a source's TileJSON or PMTiles header, a tile, a sprite, or an image source's image. */
export type ResourceType = "Style" | "Source" | "Tile" | "SpriteJSON" | "SpriteImage" | "Image";

/**
 * MapLibre's `transformRequest`: may change a request's `url`, add `headers` or send
 * `credentials` (none are sent otherwise). Return undefined to leave the request as it is.
 * PMTiles range requests are not passed through it.
 */
export type RequestTransformFunction = (
  url: string,
  resourceType: ResourceType,
) => { url: string; headers?: Record<string, string>; credentials?: RequestCredentials } | undefined;

/**
 * What `getSource` gives, with MapLibre's members for its type: GeoJSON `setData` and cluster queries (null without
 * clustering; `limit` 10 by default, Infinity for all); image, video and canvas `setCoordinates` (corners clockwise from the
 * top left), `updateImage`, `play` and `pause` (a playing canvas is redrawn every frame), `getVideo`, `getCanvas`.
 */
export interface Source {
  id: string;
  type: string;
  setData?(data: unknown): void;
  getClusterExpansionZoom?(clusterId: number): Promise<number | null>;
  getClusterChildren?(clusterId: number): Promise<GeoJSONFeature[] | null>;
  getClusterLeaves?(clusterId: number, limit?: number, offset?: number): Promise<GeoJSONFeature[] | null>;
  setCoordinates?(coordinates: number[][]): Source;
  updateImage?(options: { url?: string; image?: TexImageSource; coordinates?: number[][] }): Source;
  play?(): Source;
  pause?(): Source;
  getVideo?(): HTMLVideoElement | undefined;
  getCanvas?(): HTMLCanvasElement | undefined;
}

/**
 * Defaults: `center`, `zoom`, `bearing`, `pitch` 0; `workerCount` 0 (half the hardware threads, 1 to 4); `fontFamily` "sans-serif";
 * zoom 0-22, pitch 0-85; `attributionControl`, `interactive`, handlers true; `strict` false (else a `warning` names what is left out).
 * `workerUrl`, `wasmUrl` and the GeoJSON worker's are next to this module; `bounds` replaces `center` and `zoom` (README: the rest).
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
  strict?: boolean;
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
  transformRequest?: RequestTransformFunction;
}

/** Mouse events the map fires, and with a layer id fires for that layer's features (`mouseenter` and `mouseleave` only with one). */
export type MapMouseEventType =
  | "mousedown"
  | "mouseup"
  | "mouseover"
  | "mouseout"
  | "mousemove"
  | "click"
  | "dblclick"
  | "contextmenu"
  | "mouseenter"
  | "mouseleave";

export type MapEventType =
  | MapMouseEventType
  | "load"
  | "styledata"
  | "styleimagemissing"
  | "render"
  | "idle"
  | "error"
  | "warning"
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
 * `load` fires at the first drawn view, `render` after each frame, `idle` when the map settles;
 * camera events as MapLibre's (`originalEvent`: a gesture's DOM event). Mouse events carry the `point`
 * (CSS pixels), its `lngLat` and their `features`; `styleimagemissing` the `id` of a missing image; `warning` the `warnings`.
 */
export interface MapEvent {
  type: MapEventType;
  target: Map;
  error?: Error;
  originalEvent?: Event;
  point?: { x: number; y: number };
  lngLat?: LngLat;
  features?: MapGeoJSONFeature[];
  id?: string;
  warnings?: StyleWarning[];
}

/** Something the style uses that is not drawn: where (`layers[3].paint.line-blur`), its layer's id, and why. */
export interface StyleWarning {
  path: string;
  layer?: string;
  message: string;
}

export type MapEventListener = (event: MapEvent) => void;

/**
 * `transformStyle(previous, next)` makes the style drawn from the one asked for and the one drawn
 * before (undefined at first), as MapLibre's `setStyle` option: say, to keep overlays across basemaps.
 */
export interface StyleSwapOptions {
  transformStyle?: (previous: StyleSpecification | undefined, next: StyleSpecification) => StyleSpecification;
}

/**
 * A layer's paint for one feature (`Map.evaluatePaint`): `color` (and the circle `stroke`, the label
 * `halo`) as straight RGBA, `width` of lines, `radius` and `strokeWidth` of circles, `haloWidth` of labels.
 */
export interface PaintValues {
  color: number[];
  width: number;
  radius: number;
  stroke: number[];
  strokeWidth: number;
  halo: number[];
  haloWidth: number;
}

/** Where a tracked place is: CSS pixels from the canvas's top-left corner, and whether the terrain hides it. */
export interface ScreenPosition {
  x: number;
  y: number;
  covered: boolean;
}

/**
 * `pixelRatio`: device pixels per CSS pixel (the screen's by default); `type` and `quality` as
 * `HTMLCanvasElement.toBlob` takes them (PNG by default); `maxSize`: the largest side drawn at once
 * (the GPU's limit by default), bigger images are drawn in parts and joined.
 */
export interface ToBlobOptions {
  pixelRatio?: number;
  type?: string;
  quality?: number;
  maxSize?: number;
}

/** A place followed on screen (`Map.track`). */
export interface Tracker {
  getLngLat(): LngLat;
  setLngLat(lnglat: LngLatLike): this;
  remove(): void;
}

/** One input handler: `enable`, `disable`, `isEnabled`, as MapLibre's `map.scrollZoom` and the like. */
export interface Handler {
  enable(): void;
  disable(): void;
  isEnabled(): boolean;
}
