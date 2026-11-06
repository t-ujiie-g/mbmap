import { type Bounds, clampBounds, type TileSource, validBounds } from "./common.ts";

/** A link of an OGC API document. */
export interface OGCLink {
  href: string;
  rel: string;
  type?: string;
  title?: string;
}

/**
 * A collection of an OGC API: `bounds` its first spatial extent; `itemsUrl` its GeoJSON items (OGC
 * API - Features); `vectorTilesUrl` and `mapTilesUrl` its tileset lists (OGC API - Tiles); `mapUrl`
 * its map (OGC API - Maps). URLs are absolute.
 */
export interface OGCCollection {
  id: string;
  title?: string;
  description?: string;
  bounds?: Bounds;
  crs: string[];
  itemType?: string;
  itemsUrl?: string;
  vectorTilesUrl?: string;
  mapTilesUrl?: string;
  mapUrl?: string;
}

const REL = "http://www.opengis.net/def/rel/ogc/1.0/";
const GEOJSON = /geo\+json|application\/json/;

const record = (v: unknown): Record<string, unknown> => (v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : {});
const str = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);

/** The links of `doc`, their `href`s resolved against `base`. */
export function ogcLinks(doc: unknown, base: string): OGCLink[] {
  const links = record(doc).links;
  if (!Array.isArray(links)) return [];
  return links.flatMap((l) => {
    const { href, rel, type, title } = record(l);
    if (typeof href !== "string" || typeof rel !== "string") return [];
    try {
      return [{ href: new URL(href, base).href, rel, type: str(type), title: str(title) }];
    } catch {
      return [];
    }
  });
}

/** The first link of `links` with one of `rels` (short or full OGC names), preferring a `type` matching `prefer`. */
export function ogcLink(links: OGCLink[], rels: string[], prefer?: RegExp): string | undefined {
  const matching = links.filter((l) => rels.some((r) => l.rel === r || l.rel === REL + r));
  return (prefer && matching.find((l) => l.type && prefer.test(l.type)))?.href ?? matching[0]?.href;
}

/** The collections of an OGC API `/collections` document (`base`: its URL). */
export function readOGCCollections(doc: unknown, base: string): OGCCollection[] {
  const collections = record(doc).collections;
  if (!Array.isArray(collections)) throw new Error("mbmap: services: not an OGC API collections document");
  return collections.map((c) => readOGCCollection(c, base));
}

/** One collection of an OGC API (`/collections/{id}`; `base`: its URL). */
export function readOGCCollection(doc: unknown, base: string): OGCCollection {
  const c = record(doc);
  const links = ogcLinks(c, base);
  const bbox = record(record(c.extent).spatial).bbox;
  const box = Array.isArray(bbox) ? (Array.isArray(bbox[0]) ? bbox[0] : bbox) : undefined;
  const corners = Array.isArray(box) ? (box.length === 6 ? [box[0], box[1], box[3], box[4]] : box) : undefined;
  return {
    id: String(c.id ?? ""),
    title: str(c.title),
    description: str(c.description),
    bounds: validBounds(corners as number[] | undefined),
    crs: Array.isArray(c.crs) ? c.crs.filter((x): x is string => typeof x === "string") : [],
    itemType: str(c.itemType),
    itemsUrl: ogcLink(links, ["items"], GEOJSON),
    vectorTilesUrl: ogcLink(links, ["tilesets-vector"]),
    mapTilesUrl: ogcLink(links, ["tilesets-map"]),
    mapUrl: ogcLink(links, ["map"], /image\/png/),
  };
}

const WEB_MERCATOR_QUAD = /WebMercatorQuad$/;

/** Whether a tileset (or an entry of a tileset list) is on the WebMercatorQuad tile matrix set. */
export function isWebMercatorQuad(tileset: unknown): boolean {
  const t = record(tileset);
  return WEB_MERCATOR_QUAD.test(str(t.tileMatrixSetURI) ?? "") || WEB_MERCATOR_QUAD.test(str(t.tileMatrixSetId) ?? "") ||
    WEB_MERCATOR_QUAD.test(ogcLinks(t, "http://x/").find((l) => /tiling-scheme$/.test(l.rel))?.href ?? "");
}

/** The URL of the WebMercatorQuad tileset in a tileset list (`base`: its URL), or undefined. */
export function ogcTilesetUrl(list: unknown, base: string): string | undefined {
  const sets = record(list).tilesets;
  const set = Array.isArray(sets) ? sets.find(isWebMercatorQuad) : undefined;
  return set && ogcLink(ogcLinks(set, base), ["self"], /json/);
}

/**
 * A source for an OGC API tileset on WebMercatorQuad (`base`: its URL): vector for `dataType:
 * "vector"` (Mapbox vector tiles), raster otherwise, zooms from its `tileMatrixSetLimits`.
 */
export function ogcTileSource(tileset: unknown, base: string): TileSource {
  const t = record(tileset);
  if (!isWebMercatorQuad(t)) throw new Error("mbmap: services: the tileset is not on WebMercatorQuad");
  const vector = t.dataType === "vector";
  const item = ogcLink(ogcLinks(t, base), ["item"], vector ? /mapbox-vector-tile|mvt|protobuf/ : /image\/(png|jpeg|webp)/);
  if (!item) throw new Error("mbmap: services: the tileset has no tile URL");
  const tiles = decodeURI(item).replace(/\{tileMatrix\}/g, "{z}").replace(/\{tileRow\}/g, "{y}").replace(/\{tileCol\}/g, "{x}");
  const limits = Array.isArray(t.tileMatrixSetLimits) ? t.tileMatrixSetLimits.map((l) => Number(record(l).tileMatrix)).filter(Number.isInteger) : [];
  const box = record(t.boundingBox);
  const lower = box.lowerLeft, upper = box.upperRight;
  const bounds = Array.isArray(lower) && Array.isArray(upper) && /CRS84|4326/.test(String(box.crs ?? "CRS84")) ? validBounds([lower[0], lower[1], upper[0], upper[1]]) : undefined;
  return {
    type: vector ? "vector" : "raster",
    tiles: [tiles],
    ...(limits.length && { minzoom: Math.min(...limits), maxzoom: Math.max(...limits) }),
    ...(bounds && { bounds: clampBounds(bounds) }),
  };
}
