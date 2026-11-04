// Camera options of the facade, turned into the number arrays the engine
// takes (bundle/main/main.mbt `target_of`, `limits_of`, `map_camera_for_bounds`).
// Import-free, so that `npm test` can load it.

/** `[lng, lat]` or `{ lng, lat }`, as in MapLibre. */
export type LngLatLike = [number, number] | { lng: number; lat: number };

export interface LngLat {
  lng: number;
  lat: number;
}

/** A screen point in CSS pixels from the map's top-left corner: `[x, y]` or `{ x, y }`. */
export type PointLike = [number, number] | { x: number; y: number };

/** `[[west, south], [east, north]]`, `[west, south, east, north]` or an `LngLatBounds`. */
export type LngLatBoundsLike = LngLatBounds | [LngLatLike, LngLatLike] | [number, number, number, number];

/** Pixels on each side, or the same on all four. */
export type PaddingOptions = number | { top?: number; right?: number; bottom?: number; left?: number };

/** A box in longitude and latitude, as MapLibre's `LngLatBounds` (west may exceed east across the antimeridian). */
export class LngLatBounds {
  readonly west: number;
  readonly south: number;
  readonly east: number;
  readonly north: number;

  constructor(west: number, south: number, east: number, north: number) {
    this.west = west;
    this.south = south;
    this.east = east;
    this.north = north;
  }

  static convert(b: LngLatBoundsLike): LngLatBounds {
    if (b instanceof LngLatBounds) return b;
    if (b.length === 4) return new LngLatBounds(b[0], b[1], b[2], b[3]);
    const sw = toLngLat(b[0]);
    const ne = toLngLat(b[1]);
    return new LngLatBounds(sw.lng, sw.lat, ne.lng, ne.lat);
  }

  getWest(): number {
    return this.west;
  }
  getSouth(): number {
    return this.south;
  }
  getEast(): number {
    return this.east;
  }
  getNorth(): number {
    return this.north;
  }
  getSouthWest(): LngLat {
    return { lng: this.west, lat: this.south };
  }
  getNorthEast(): LngLat {
    return { lng: this.east, lat: this.north };
  }
  getCenter(): LngLat {
    return { lng: (this.west + this.east) / 2, lat: (this.south + this.north) / 2 };
  }
  /** `[[west, south], [east, north]]`. */
  toArray(): [[number, number], [number, number]] {
    return [[this.west, this.south], [this.east, this.north]];
  }
}

export function toLngLat(c: LngLatLike): LngLat {
  return Array.isArray(c) ? { lng: c[0], lat: c[1] } : { lng: c.lng, lat: c.lat };
}

export function toPoint(p: PointLike): { x: number; y: number } {
  return Array.isArray(p) ? { x: p[0], y: p[1] } : { x: p.x, y: p.y };
}

export function toPadding(p: PaddingOptions | undefined): [number, number, number, number] {
  if (p === undefined) return [0, 0, 0, 0];
  if (typeof p === "number") return [p, p, p, p];
  return [p.top ?? 0, p.right ?? 0, p.bottom ?? 0, p.left ?? 0];
}

/** What every camera move takes, as in MapLibre's `CameraOptions` (`around` keeps that point still). */
export interface CameraOptions {
  center?: LngLatLike;
  zoom?: number;
  bearing?: number;
  pitch?: number;
  around?: LngLatLike;
}

/**
 * - `duration` (ms; default 500 for `easeTo`), `easing` (0-1 to 0-1), `offset` (where the
 *   center ends up, in pixels from the screen center), `animate: false` to jump.
 * - `essential`: animate even when the user prefers reduced motion.
 */
export interface AnimationOptions {
  duration?: number;
  easing?: (t: number) => number;
  offset?: PointLike;
  animate?: boolean;
  essential?: boolean;
}

export type EaseToOptions = CameraOptions & AnimationOptions;

/**
 * MapLibre's `flyTo` options: `curve` (ρ, default 1.42), `speed` (screenfuls a second,
 * default 1.2), `screenSpeed`, `maxDuration` (longer flights jump), `minZoom` (the
 * lowest zoom on the way).
 */
export interface FlyToOptions extends EaseToOptions {
  curve?: number;
  speed?: number;
  screenSpeed?: number;
  maxDuration?: number;
  minZoom?: number;
}

/** `padding` around the box, `bearing` to look at it with, `maxZoom` to stop at; `linear: true` eases instead of flying. */
export interface FitBoundsOptions extends FlyToOptions {
  padding?: PaddingOptions;
  maxZoom?: number;
  linear?: boolean;
}

function num(v: number | undefined): number {
  if (v === undefined) return NaN;
  if (!Number.isFinite(v)) throw new TypeError(`mbmap: camera values must be finite numbers: ${String(v)}`);
  return v;
}

/** The engine's move target: center, zoom, bearing, pitch, around (NaN for none), offset. */
export function targetArray(o: EaseToOptions): number[] {
  const c = o.center === undefined ? undefined : toLngLat(o.center);
  const a = o.around === undefined ? undefined : toLngLat(o.around);
  const off = o.offset === undefined ? { x: 0, y: 0 } : toPoint(o.offset);
  return [num(c?.lng), num(c?.lat), num(o.zoom), num(o.bearing), num(o.pitch), num(a?.lng), num(a?.lat), num(off.x), num(off.y)];
}

/** The engine's fly options: duration, curve, speed, screen speed, max duration, min zoom. */
export function flyArray(o: FlyToOptions): number[] {
  return [num(o.duration), num(o.curve), num(o.speed), num(o.screenSpeed), num(o.maxDuration), num(o.minZoom)];
}

/**
 * The default zoom and pitch ranges (`Transform::new` and `MAX_PITCH` in core/transform.mbt; element/parse.ts
 * mirrors them) and the highest zoom a limit or a layer's range may take (the style spec's layer `maxzoom`).
 */
export const MIN_ZOOM = 0;
export const MAX_ZOOM = 22;
export const MAX_ZOOM_LIMIT = 24;
export const MIN_PITCH = 0;
export const MAX_PITCH = 85;

/** Zoom and pitch ranges and the bounds the camera keeps to. */
export interface Limits {
  minZoom: number;
  maxZoom: number;
  minPitch: number;
  maxPitch: number;
  maxBounds: LngLatBounds | null;
}

/** Throws unless the limits are finite, within `MIN_ZOOM`-`MAX_ZOOM_LIMIT` and `MIN_PITCH`-`MAX_PITCH`, min not above max. */
export function checkLimits(l: Limits): void {
  for (const v of [l.minZoom, l.maxZoom, l.minPitch, l.maxPitch]) {
    if (!Number.isFinite(v)) throw new TypeError(`mbmap: zoom and pitch limits must be finite numbers: ${String(v)}`);
  }
  if (l.minZoom > l.maxZoom || l.minPitch > l.maxPitch || l.minZoom < MIN_ZOOM || l.maxZoom > MAX_ZOOM_LIMIT || l.minPitch < MIN_PITCH || l.maxPitch > MAX_PITCH) {
    throw new RangeError("mbmap: zoom limits must lie in 0-24 and pitch limits in 0-85, min not above max");
  }
}

export function limitsArray(l: Limits): number[] {
  const b = l.maxBounds;
  return [l.minZoom, l.maxZoom, l.minPitch, l.maxPitch, b ? b.west : NaN, b ? b.south : 0, b ? b.east : 0, b ? b.north : 0];
}

/** The engine's `camera_for_bounds` input. */
export function fitArray(b: LngLatBounds, o: FitBoundsOptions & { bearing?: number }): number[] {
  const off = o.offset === undefined ? { x: 0, y: 0 } : toPoint(o.offset);
  return [b.west, b.south, b.east, b.north, num(o.bearing ?? 0), ...toPadding(o.padding).map(num), num(off.x), num(off.y), num(o.maxZoom)];
}

/** The handlers the engine knows, in the order of bundle/main/main.mbt `handlers`. */
export const HANDLERS = ["dragPan", "scrollZoom", "boxZoom", "dragRotate", "keyboard", "doubleClickZoom", "touchZoomRotate", "touchPitch"] as const;
export type HandlerName = (typeof HANDLERS)[number];
