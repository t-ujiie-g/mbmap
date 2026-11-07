// Pure parts of mbmap/services shared by the readers: query strings, Web Mercator grids and the
// sources they make. Import-free, for `npm test`.

/** `[west, south, east, north]` in degrees. */
export type Bounds = [number, number, number, number];

/** A style source as MapLibre's: tiles from a URL template with the engine's placeholders. */
export interface TileSource {
  type: "raster" | "vector";
  tiles: string[];
  tileSize?: number;
  minzoom?: number;
  maxzoom?: number;
  bounds?: Bounds;
  attribution?: string;
}

/**
 * mbmap's own source of a raster in another CRS (`crs`, an EPSG code), drawn on Web Mercator tiles by mbmap/data's worker:
 * a WMTS set (`grid`) or one GetMap per tile (`image`, its box northing first when `northFirst`); npm/README.md has the fields.
 */
export interface ReprojectedSource {
  type: "reprojected";
  crs: number;
  grid?: { template: string; matrices: ReprojectedMatrix[] };
  image?: { template: string; northFirst: boolean };
  tileSize?: 256 | 512;
  minzoom?: number;
  maxzoom?: number;
  bounds?: Bounds;
  attribution?: string;
}

/** The pixels on a side of a `ReprojectedSource`'s tiles unless its `tileSize` says otherwise. */
export const REPROJECTED_TILE_SIZE = 256;

/** One matrix of a `ReprojectedSource`'s grid. */
export interface ReprojectedMatrix {
  id: string;
  resolution: number;
  x: number;
  y: number;
  width: number;
  height: number;
  cols: number;
  rows: number;
}

/** The sphere Web Mercator and OGC's degrees are reckoned on, in meters. */
export const EARTH_RADIUS = 6378137;

/** Half the side of the Web Mercator square, in meters (EPSG:3857). */
export const MERCATOR_HALF = Math.PI * EARTH_RADIUS;

/** The side of the Web Mercator square, in meters. */
export const MERCATOR_WORLD = 2 * MERCATOR_HALF;

/** The latitude Web Mercator's square ends at. */
export const MERCATOR_LATITUDE = 85.051129;

const MERCATOR_CODES = new Set(["3857", "900913", "102100", "102113", "3785"]);

/** Whether `crs` (`EPSG:3857`, an OGC URN or URL, or a bare code) names Web Mercator. */
export function isWebMercator(crs: string | number | undefined): boolean {
  const code = /(\d+)\D*$/.exec(String(crs ?? ""))?.[1];
  return code !== undefined && MERCATOR_CODES.has(code);
}

/** The zoom whose `tileSize`-pixel tiles have `resolution` meters per pixel, or NaN when none is within 1e-6. */
export function mercatorZoom(resolution: number, tileSize: number): number {
  const z = Math.log2(MERCATOR_WORLD / (tileSize * resolution));
  const rounded = Math.round(z);
  return Math.abs(z - rounded) < 1e-6 && rounded >= 0 ? rounded : NaN;
}

/** OGC's standardized pixel size, 0.28 mm, which scale denominators are reckoned in. */
export const OGC_PIXEL_METERS = 0.00028;

/** The EPSG code `crs` names (`EPSG:6677`, an OGC URN or URL; CRS84 as 4326), or undefined. */
export function epsgCode(crs: string): number | undefined {
  if (/CRS:?84$/i.test(crs)) return 4326;
  const code = /EPSG/i.test(crs) ? /(\d+)\D*$/.exec(crs)?.[1] : undefined;
  return code === undefined ? undefined : Number(code);
}

// EPSG geographic CRSs (latitude first, in degrees).
const GEOGRAPHIC = new Set([4326, 4612, 6668, 4301, 4258, 4269, 4283, 4019]);

/**
 * Whether `crs` lists its northing (latitude) first, as WMS 1.3.0 boxes and WMTS corners in it are written: geographic
 * CRSs and Japan's plane rectangular zones (JGD2000, JGD2011); CRS84 does not.
 */
export function northFirst(crs: string): boolean {
  if (/CRS:?84$/i.test(crs)) return false;
  const code = epsgCode(crs) ?? 0;
  return GEOGRAPHIC.has(code) || (code >= 2443 && code <= 2461) || (code >= 6669 && code <= 6687);
}

/** Meters per unit of `crs`: OGC's degree on the EARTH_RADIUS sphere for geographic CRSs, else 1. */
export const metersPerUnit = (crs: string): number => (GEOGRAPHIC.has(epsgCode(crs) ?? 0) ? MERCATOR_WORLD / 360 : 1);

/** The first zoom whose `tileSize`-pixel tiles are at least as fine as `meters` per pixel (0 to 22). */
export const zoomForResolution = (meters: number, tileSize: number): number =>
  Math.min(22, Math.max(0, Math.ceil(Math.log2(MERCATOR_WORLD / (tileSize * meters)) - 1e-9)));

/** Meters in Web Mercator of `[lng, lat]` degrees. */
export function lngLatToMercator(lng: number, lat: number): [number, number] {
  return [(lng / 180) * MERCATOR_HALF, Math.log(Math.tan(((90 + lat) * Math.PI) / 360)) * EARTH_RADIUS];
}

/** Meters per pixel of Web Mercator at `zoom`, with MapLibre's 512-pixel tiles. */
export const zoomResolution = (zoom: number): number => MERCATOR_WORLD / (512 * 2 ** zoom);

/** `[minX, minY, maxX, maxY]` in EPSG:3857 meters. */
export type MercatorBox = [number, number, number, number];

/** A single image's URL for `bbox` at `width` by `height` pixels, `pixelRatio` device pixels to a CSS pixel. */
export type ImageRequest = (bbox: MercatorBox, width: number, height: number, pixelRatio: number) => string;

/** The side of OpenLayers' window for a click, in pixels, and the click's pixel in it. */
export const CLICK_PIXELS = 101;
export const CLICK_PIXEL = 50;

/** OpenLayers' window for a click: CLICK_PIXELS square at `resolution` around `[x, y]`, the click at pixel CLICK_PIXEL. */
export function clickWindow(x: number, y: number, resolution: number): MercatorBox {
  const half = (CLICK_PIXELS / 2) * resolution;
  return [x - half, y - half, x + half, y + half];
}

/** The most pixels on a side `imageView` asks for by default. */
export const MAX_IMAGE_SIZE = 4096;

/**
 * The image of `bounds` (degrees, cut to Web Mercator's latitudes) on a map at `zoom`: its EPSG:3857 box and size at
 * `pixelRatio`, at most `maxSize` pixels on a side, and its corners in degrees (top left, top right, bottom right, bottom left).
 */
export function imageView(bounds: Bounds, zoom: number, pixelRatio: number, maxSize = MAX_IMAGE_SIZE) {
  const lat = (v: number) => Math.min(Math.max(v, -MERCATOR_LATITUDE), MERCATOR_LATITUDE);
  const [x0, y0] = lngLatToMercator(bounds[0], lat(bounds[1]));
  const [x1, y1] = lngLatToMercator(bounds[2], lat(bounds[3]));
  const scale = Math.min(pixelRatio / zoomResolution(zoom), maxSize / Math.max(x1 - x0, y1 - y0));
  const [west, south] = mercatorToLngLat(x0, y0);
  const [east, north] = mercatorToLngLat(x1, y1);
  return {
    bbox: [x0, y0, x1, y1] as MercatorBox,
    width: Math.max(1, Math.round((x1 - x0) * scale)),
    height: Math.max(1, Math.round((y1 - y0) * scale)),
    coordinates: [[west, north], [east, north], [east, south], [west, south]],
  };
}

/** Degrees of `[x, y]` meters in Web Mercator. */
export function mercatorToLngLat(x: number, y: number): [number, number] {
  return [(x / MERCATOR_HALF) * 180, (Math.atan(Math.exp(y / EARTH_RADIUS)) * 360) / Math.PI - 90];
}

// A query parameter's name, decoded unless its escapes are malformed.
function paramName(param: string): string {
  const name = param.split("=")[0];
  try {
    return decodeURIComponent(name);
  } catch {
    return name;
  }
}

/**
 * `base` with `params` added to its query, replacing parameters of the same name in any letter case
 * (a URL from a capabilities document may carry `map=` or a token). Values are percent-encoded but
 * the engine's placeholders (`{bbox-epsg-3857}`, `{z}`, …) are kept.
 */
export function withQuery(base: string, params: Record<string, string | number | undefined>): string {
  const hash = base.indexOf("#");
  const url = hash < 0 ? base : base.slice(0, hash);
  const q = url.indexOf("?");
  const names = new Set(Object.keys(params).map((k) => k.toLowerCase()));
  const kept = q < 0 ? [] : url.slice(q + 1).split("&").filter((p) => p && !names.has(paramName(p).toLowerCase()));
  const added = Object.entries(params)
    .filter(([, v]) => v !== undefined)
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v)).replace(/%7B([\w-]+)%7D/g, "{$1}")}`);
  const all = [...kept, ...added];
  return `${q < 0 ? url : url.slice(0, q)}${all.length ? `?${all.join("&")}` : ""}`;
}

/**
 * A template naming the zooms `from`, `from + 1`, … by `ids` with `{z}`, when every id is the zoom
 * between one prefix and one suffix (`"3"`, `"EPSG:3857:3"`, `"L03"` is not); otherwise null.
 */
export function zoomTemplate(ids: string[], from: number): string | null {
  const z = String(from);
  const at = ids[0]?.lastIndexOf(z) ?? -1;
  if (at < 0) return null;
  const prefix = ids[0].slice(0, at);
  const suffix = ids[0].slice(at + z.length);
  return ids.every((id, i) => id === `${prefix}${from + i}${suffix}`) ? `${prefix}{z}${suffix}` : null;
}

/**
 * `url` resolved against `base` (the document it was read from) when there is one; URL templates
 * keep their braces (`{TileMatrix}`, `{z}`).
 */
export function resolved(url: string, base: string | undefined): string {
  if (base === undefined) return url;
  try {
    return new URL(url, base).href.replace(/%7B(\w+)%7D/gi, "{$1}");
  } catch {
    return url;
  }
}

/** `bounds` when it holds four finite numbers, west ≤ east and south ≤ north; otherwise undefined. */
export function validBounds(bounds: number[] | undefined): Bounds | undefined {
  if (!bounds || bounds.length !== 4 || !bounds.every(Number.isFinite)) return undefined;
  const [w, s, e, n] = bounds;
  return w <= e && s <= n ? [w, s, e, n] : undefined;
}

/** `bounds` cut to the longitudes and latitudes a style source's `bounds` take. */
export function clampBounds(bounds: Bounds): Bounds {
  const [w, s, e, n] = bounds;
  return [Math.max(w, -180), Math.max(s, -90), Math.min(e, 180), Math.min(n, 90)];
}

/** `url` without its query, fragment and trailing slashes: a service's or layer's base URL. */
export const serviceBase = (url: string): string => url.replace(/[?#].*$/, "").replace(/\/+$/, "");
