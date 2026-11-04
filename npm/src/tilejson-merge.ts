// TileJSON documents merged into their sources, loaded with the first style that has one.
// Import-free but for tilejson.ts, so that `npm test` can load it.
import { setOwn, type StyleSpecification } from "./style.ts";
import { withoutSources } from "./tilejson.ts";

/** The TileJSON keys a source takes, as MapLibre's `loadTileJson` picks them; the source's own win. */
const KEYS = ["tiles", "minzoom", "maxzoom", "attribution", "bounds", "scheme", "tileSize", "encoding"] as const;

/**
 * The style with each source of `urls` (`tileJSONUrls`) completed from `documents` (TileJSON by URL); tile templates
 * resolve against their document's URL. A source whose document has not come is left out, with
 * its layers, until it has.
 */
export function withTileJSON(
  style: StyleSpecification,
  urls: Map<string, string>,
  documents: Map<string, unknown>,
  resolve: (template: string, base: URL) => string,
): StyleSpecification {
  const sources = { ...style.sources };
  const pending = new Set<string>();
  for (const [id, url] of urls) {
    const doc = documents.get(url) as Record<string, unknown> | undefined;
    if (!doc || typeof doc !== "object") {
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
    setOwn(sources, id, merged);
  }
  return withoutSources({ ...style, sources }, pending);
}
