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

/** Half the side of the Web Mercator square, in meters (EPSG:3857). */
export const MERCATOR_HALF = Math.PI * 6378137;

const MERCATOR_CODES = new Set(["3857", "900913", "102100", "102113", "3785", "3587"]);

/** Whether `crs` (`EPSG:3857`, an OGC URN or URL, or a bare code) names Web Mercator. */
export function isWebMercator(crs: string | number | undefined): boolean {
  const code = /(\d+)\D*$/.exec(String(crs ?? ""))?.[1];
  return code !== undefined && MERCATOR_CODES.has(code);
}

/** The zoom whose `tileSize`-pixel tiles have `resolution` meters per pixel, or NaN when none is within 1e-6. */
export function mercatorZoom(resolution: number, tileSize: number): number {
  const z = Math.log2((2 * MERCATOR_HALF) / (tileSize * resolution));
  const rounded = Math.round(z);
  return Math.abs(z - rounded) < 1e-6 && rounded >= 0 ? rounded : NaN;
}

/** OGC's standardized pixel size, 0.28 mm, which scale denominators are reckoned in. */
export const OGC_PIXEL_METERS = 0.00028;

/** Meters in Web Mercator of `[lng, lat]` degrees. */
export function lngLatToMercator(lng: number, lat: number): [number, number] {
  return [(lng / 180) * MERCATOR_HALF, Math.log(Math.tan(((90 + lat) * Math.PI) / 360)) * 6378137];
}

/** Meters per pixel of Web Mercator at `zoom`, with MapLibre's 512-pixel tiles. */
export const zoomResolution = (zoom: number): number => (2 * MERCATOR_HALF) / (512 * 2 ** zoom);

/**
 * A single image's URL for `bbox` (`[minX, minY, maxX, maxY]` in EPSG:3857 meters) at `width` by `height`
 * pixels, `pixelRatio` device pixels to a CSS pixel.
 */
export type ImageRequest = (bbox: Bounds, width: number, height: number, pixelRatio: number) => string;

/** OpenLayers' window for a click: 101 by 101 pixels at `resolution` around `[x, y]`, the click at pixel 50, 50. */
export function clickWindow(x: number, y: number, resolution: number): Bounds {
  const half = 50.5 * resolution;
  return [x - half, y - half, x + half, y + half];
}

/** Degrees of `[x, y]` meters in Web Mercator. */
export function mercatorToLngLat(x: number, y: number): [number, number] {
  return [(x / MERCATOR_HALF) * 180, (Math.atan(Math.exp(y / 6378137)) * 360) / Math.PI - 90];
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
  const kept = q < 0 ? [] : url.slice(q + 1).split("&").filter((p) => p && !names.has(decodeURIComponent(p.split("=")[0]).toLowerCase()));
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
