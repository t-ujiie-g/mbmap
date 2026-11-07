import { type Bounds, withQuery } from "./common.ts";

/** A GeoJSON FeatureCollection as the services return it; `exceeded` when paging stopped at a cap with features left. */
export interface FeatureCollection {
  type: "FeatureCollection";
  features: unknown[];
  exceeded?: boolean;
}

/** The most features one fetch gathers across its pages, and the most pages it asks for. */
export const MAX_FEATURES = 1_000_000;
export const MAX_PAGES = 10_000;

/** `bbox` (degrees), `limit` per page, `datetime` and `properties` of an OGC API - Features items request. */
export interface OGCItemsOptions {
  bbox?: Bounds;
  limit?: number;
  datetime?: string;
  properties?: string[];
}

/** The first items page of a collection's `itemsUrl`. */
export function ogcItemsUrl(itemsUrl: string, options: OGCItemsOptions = {}): string {
  return withQuery(itemsUrl, {
    bbox: options.bbox?.join(","),
    limit: options.limit,
    datetime: options.datetime,
    properties: options.properties?.join(","),
  });
}

/**
 * `typeName`; `bbox` in degrees; `count` per page; `startIndex`; `outputFormat` (default the
 * first GeoJSON one the service offers); `crs` for the output (`SRSNAME`, default the type's own).
 */
export interface WFSFeatureOptions {
  typeName: string;
  bbox?: Bounds;
  count?: number;
  startIndex?: number;
  outputFormat?: string;
  crs?: string;
}

/** The GeoJSON output format among `formats`, or undefined. */
export function geojsonFormat(formats: string[]): string | undefined {
  return formats.find((f) => /geo\+?json/i.test(f)) ?? formats.find((f) => /json/i.test(f));
}

/**
 * A WFS GetFeature URL (`getFeatureUrl`, `version`): 2.0's TYPENAMES and COUNT, older MAXFEATURES;
 * a bbox goes as EPSG:4326 latitude first (WFS 1.1 and 2.0 take the CRS's axis order), WFS 1.0's
 * as longitude first.
 */
export function wfsFeatureUrl(getFeatureUrl: string, version: string, options: WFSFeatureOptions): string {
  const v2 = version.startsWith("2.");
  const v10 = version.startsWith("1.0");
  const b = options.bbox;
  return withQuery(getFeatureUrl, {
    SERVICE: "WFS",
    VERSION: version,
    REQUEST: "GetFeature",
    [v2 ? "TYPENAMES" : "TYPENAME"]: options.typeName,
    OUTPUTFORMAT: options.outputFormat,
    [v2 ? "COUNT" : "MAXFEATURES"]: options.count,
    STARTINDEX: options.startIndex || undefined,
    SRSNAME: options.crs,
    BBOX: b && (v10 ? b.join(",") : `${b[1]},${b[0]},${b[3]},${b[2]},urn:ogc:def:crs:EPSG::4326`),
  });
}

/** `where` (default `1=1`), `bbox` in degrees, `outFields` (default all), `offset` and `count` of an ArcGIS layer query. */
export interface ArcGISQueryOptions {
  where?: string;
  bbox?: Bounds;
  outFields?: string[];
  offset?: number;
  count?: number;
}

/** An ArcGIS FeatureServer or MapServer layer's `query` for GeoJSON in EPSG:4326 (`layerUrl`: `.../FeatureServer/0`). */
export function arcgisQueryUrl(layerUrl: string, options: ArcGISQueryOptions = {}, format = "geojson"): string {
  const base = layerUrl.replace(/[?#].*$/, "").replace(/\/+$/, "");
  const b = options.bbox;
  return withQuery(`${base}/query`, {
    where: options.where ?? "1=1",
    outFields: options.outFields?.join(",") ?? "*",
    ...(b && { geometry: b.join(","), geometryType: "esriGeometryEnvelope", inSR: 4326, spatialRel: "esriSpatialRelIntersects" }),
    outSR: 4326,
    resultOffset: options.offset,
    resultRecordCount: options.count,
    f: format,
  });
}

/** The format `arcgisFeatures` asks a layer for by default (services.ts `ArcGISFeatureOptions`): PBF, else GeoJSON, else JSON, as `supportedQueryFormats` lists them. */
export function arcgisFormat(layer: unknown): "geojson" | "json" | "pbf" {
  const formats = (layer as { supportedQueryFormats?: unknown } | null)?.supportedQueryFormats;
  const listed = typeof formats === "string" ? formats.split(",").map((f) => f.trim().toLowerCase()) : [];
  return listed.includes("pbf") ? "pbf" : listed.includes("geojson") ? "geojson" : "json";
}

/** The features of a GeoJSON page; anything else throws. */
export function pageFeatures(page: unknown, what: string): unknown[] {
  const features = (page as { features?: unknown } | null)?.features;
  const error = (page as { error?: { code?: number; message?: string } } | null)?.error;
  if (error) throw new Error(`mbmap: services: ${what}: ArcGIS error ${error.code ?? ""}: ${error.message ?? ""}`);
  if (!Array.isArray(features)) throw new Error(`mbmap: services: ${what} did not answer with GeoJSON features`);
  return features;
}

/**
 * Gathers pages until `next` gives none: `next(page, features)` is the URL of the page after
 * `page` (with `features` gathered so far), or undefined. Stops at `max` features (then
 * `exceeded`) and at `MAX_PAGES`, so a server cannot keep a client paging.
 */
export async function gather(
  first: string,
  load: (url: string) => Promise<unknown>,
  next: (page: unknown, url: string, count: number) => string | undefined,
  max: number,
  what: string,
): Promise<FeatureCollection> {
  const features: unknown[] = [];
  let url: string | undefined = first;
  const seen = new Set<string>();
  for (let pages = 0; url !== undefined; pages++) {
    if (pages === MAX_PAGES || seen.has(url)) return { type: "FeatureCollection", features, exceeded: true };
    seen.add(url);
    const page = await load(url);
    const got = pageFeatures(page, what);
    for (const f of got) {
      if (features.length === max) return { type: "FeatureCollection", features, exceeded: true };
      features.push(f);
    }
    url = got.length === 0 ? undefined : next(page, url, features.length);
  }
  return { type: "FeatureCollection", features };
}
