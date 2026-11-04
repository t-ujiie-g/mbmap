// Sources given by `url` (a TileJSON document, MapLibre's way): which documents a style
// needs (tilejson-merge.ts merges them in once fetched). Imports only urls.ts (by its extension), for `npm test`.
import type { StyleSpecification } from "./style";
import { PMTILES, httpUrl, pmtilesArchive } from "./urls.ts";

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
    const archive = pmtilesArchive(src.url);
    const url = httpUrl(archive ?? src.url, base, `source "${id}": url`);
    out.set(id, archive === null ? url : PMTILES + url);
  }
  return out;
}

/** The style without `ids`' sources and their layers: sources whose TileJSON has not come. */
export function withoutSources(style: StyleSpecification, ids: Set<string>): StyleSpecification {
  const sources = { ...style.sources };
  for (const id of ids) delete sources[id];
  const layers = ids.size === 0 ? style.layers : style.layers.filter((l) => !ids.has(String((l as { source?: unknown }).source)));
  return { ...style, sources, layers };
}
