// URL handling of the facade, kept free of imports so tests can run it as is.

/** What a `transformRequest` gives: the URL to fetch, and the headers and credentials to send. */
export interface TransformedRequest {
  url: string;
  headers?: Record<string, string>;
  credentials?: RequestCredentials;
}

/** `url` resolved against `base`, refused unless http(s), so a style cannot fetch data: or blob: URLs (AGENTS.md §8.3). */
export function httpUrl(url: string | URL, base: string | URL, what: string): string {
  const u = new URL(url, base);
  if (!/^https?:$/.test(u.protocol)) throw new Error(`mbmap: ${what} must be an http(s) URL: ${u.href}`);
  return u.href;
}

/** The scheme prefix of PMTiles archives in source URLs and tile templates. */
export const PMTILES = "pmtiles://";

/** The archive URL of a `pmtiles://` URL, or null for any other. */
export function pmtilesArchive(url: string): string | null {
  return url.startsWith(PMTILES) ? url.slice(PMTILES.length) : null;
}

/** The tile URL placeholders the engine fills in, as MapLibre's `CanonicalTileID.url`. */
export const TILE_PLACEHOLDERS = ["z", "x", "y", "prefix", "ratio", "quadkey", "bbox-epsg-3857", "bbox"];

const ENCODED_PLACEHOLDER = new RegExp(`%7B(${TILE_PLACEHOLDERS.join("|")})%7D`, "g");

/** A tile template resolved against `base`, its placeholders kept: http(s), or `pmtiles://` and an http(s) archive. */
export function resolveTemplate(template: string, base: string | URL, what = "tiles"): string {
  const archive = pmtilesArchive(template);
  // URL() percent-encodes the placeholders' braces.
  const href = httpUrl(archive ?? template, base, what).replace(ENCODED_PLACEHOLDER, "{$1}");
  return archive === null ? href : PMTILES + href;
}

/** Same-origin http(s) only, so markup cannot start data:, blob: or foreign workers (AGENTS.md §8.3). */
export function workerScriptUrl(url: string | URL, base: URL, origin: string): string {
  const u = new URL(url, base);
  if (!/^https?:$/.test(u.protocol) || u.origin !== origin) {
    throw new Error(`mbmap: the worker must be a same-origin http(s) URL: ${u.href}`);
  }
  return u.href;
}

export function wasmUrl(url: string | URL, base: URL): string {
  return httpUrl(url, base, "the wasm");
}
