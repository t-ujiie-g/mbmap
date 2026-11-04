// The style as the engine takes it: tile URLs resolved, GeoJSON data split off and
// query filters as JSON text. Imports only import-free modules by their extension,
// so that `npm test` can load it.
import type { GeoJSONSource } from "./geojson";
import { isLegacyFilter, type StyleSpecification } from "./style.ts";
import { resolveTemplate } from "./urls.ts";

/** The style with tile URLs resolved against the style's own URL. */
export function resolveTiles(style: StyleSpecification, base: URL): StyleSpecification {
  const sources = Object.fromEntries(
    Object.entries(style.sources ?? {}).map(([id, s]) => {
      const tiles = (s as { tiles?: unknown })?.tiles;
      if (!Array.isArray(tiles)) return [id, s];
      return [id, { ...(s as object), tiles: tiles.map((t) => (typeof t === "string" ? resolveTemplate(t, base) : t)) }];
    }),
  );
  return { ...style, sources };
}

/** The style's GeoJSON sources, and the style without their data (only their worker needs it). */
export function splitGeoJSON(style: StyleSpecification): [GeoJSONSource[], StyleSpecification] {
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

/** A query's filter as the engine takes it: JSON text (empty for none), legacy filters converted by `convert` once loaded. */
export function filterText(filter: unknown, convert: ((filter: unknown) => unknown) | null): string {
  if (filter === undefined) return "";
  return JSON.stringify(convert && isLegacyFilter(filter) ? convert(filter) : filter);
}
