// Sources given by `url` (a TileJSON document, MapLibre's way): what the engine
// needs of them is merged in from documents fetched beforehand. Import-free, so
// that `npm test` can load it.
import type { StyleSpecification } from "./style";

/** The TileJSON keys a source takes, as MapLibre's `loadTileJson` picks them; the source's own win. */
const KEYS = ["tiles", "minzoom", "maxzoom", "attribution", "bounds", "scheme", "tileSize", "encoding"] as const;

const TYPES = new Set(["vector", "raster", "raster-dem"]);

/**
 * The absolute URL of each source's TileJSON (http(s) only), by source id; a PMTiles archive
 * (`pmtiles://` and its URL) keeps the prefix, its document read from the archive's header.
 */
export function tileJSONUrls(style: StyleSpecification, base: URL): Map<string, string> {
  const out = new Map<string, string>();
  for (const [id, s] of Object.entries(style.sources ?? {})) {
    const src = s as { type?: unknown; url?: unknown; tiles?: unknown };
    if (!TYPES.has(String(src?.type)) || typeof src.url !== "string" || Array.isArray(src.tiles)) continue;
    const pmtiles = src.url.startsWith("pmtiles://");
    const url = new URL(pmtiles ? src.url.slice(10) : src.url, base);
    if (!/^https?:$/.test(url.protocol)) throw new Error(`mbmap: source "${id}": url must be http(s): ${url.href}`);
    out.set(id, pmtiles ? `pmtiles://${url.href}` : url.href);
  }
  return out;
}

/**
 * The style with each `url` source completed from `documents` (TileJSON by URL); tile templates
 * resolve against their document's URL. A source whose document has not come is left out, with
 * its layers, until it has.
 */
export function withTileJSON(style: StyleSpecification, base: URL, documents: Map<string, unknown>, resolve: (template: string, base: URL) => string): StyleSpecification {
  const urls = tileJSONUrls(style, base);
  if (urls.size === 0) return style;
  const sources = { ...style.sources };
  const pending = new Set<string>();
  for (const [id, url] of urls) {
    const doc = documents.get(url) as Record<string, unknown> | undefined;
    if (!doc || typeof doc !== "object") {
      delete sources[id];
      pending.add(id);
      continue;
    }
    const { url: _, ...own } = sources[id] as Record<string, unknown>;
    const merged: Record<string, unknown> = {};
    for (const k of KEYS) if (doc[k] !== undefined) merged[k] = doc[k];
    Object.assign(merged, own);
    if (Array.isArray(merged.tiles)) {
      merged.tiles = merged.tiles.map((t) => (typeof t === "string" ? resolve(t, new URL(url)) : t));
    }
    sources[id] = merged;
  }
  const layers = pending.size === 0 ? style.layers : style.layers.filter((l) => !pending.has(String((l as { source?: unknown }).source)));
  return { ...style, sources, layers };
}
