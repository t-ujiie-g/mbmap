// mbmap/services: reading GIS web services (OGC WMS, WMTS, WFS and OGC API; ArcGIS REST) into
// style sources. Requests go through `transformRequest` as the map's do; no credentials otherwise.
import { readOGCCollection, readOGCCollections, type OGCCollection, ogcTileSource, ogcTilesetUrl, ogcLink, ogcLinks } from "./services/ogcapi";
import type { ArcGISService } from "./services/arcgis";
import type { TileSource } from "./services/common";
import { readWFSCapabilities, type WFSCapabilities } from "./services/wfs";
import { readWMSCapabilities, type WMSCapabilities } from "./services/wms";
import { readWMTSCapabilities, type WMTSCapabilities } from "./services/wmts";
import { withQuery } from "./services/common";
import { httpUrl, type TransformedRequest } from "./urls";

export { arcgisBounds, arcgisSource, arcgisZooms, type ArcGISService, type ArcGISSourceOptions } from "./services/arcgis";
export { isWebMercator, resolved, withQuery, type Bounds, type TileSource } from "./services/common";
export { isWebMercatorQuad, ogcLinks, ogcTileSource, ogcTilesetUrl, readOGCCollection, readOGCCollections, type OGCCollection, type OGCLink } from "./services/ogcapi";
export { readWFSCapabilities, type WFSCapabilities, type WFSFeatureType } from "./services/wfs";
export { allLayers, readWMSCapabilities, wmsSource, type WMSCapabilities, type WMSLayer, type WMSSourceOptions, type WMSStyle } from "./services/wms";
export { mercatorZooms, readWMTSCapabilities, wmtsSource, type WMTSCapabilities, type WMTSLayer, type WMTSResource, type WMTSSourceOptions, type WMTSTileMatrix, type WMTSTileMatrixSet } from "./services/wmts";

/** The most a service document may weigh, in bytes. */
export const MAX_DOCUMENT_BYTES = 32 * 1024 * 1024;

/** `transformRequest`: as the map's (asked with `"Source"`); `signal`: aborts the requests. */
export interface ServiceOptions {
  transformRequest?: (url: string, type: "Source") => TransformedRequest | undefined;
  signal?: AbortSignal;
}

/** The text at `url` (http(s), resolved against the page), refused past `MAX_DOCUMENT_BYTES`. */
async function load(url: string, options: ServiceOptions): Promise<string> {
  const href = httpUrl(url, document.baseURI, "services: the URL");
  const r = options.transformRequest?.(href, "Source");
  const res = await fetch(r ? httpUrl(r.url, document.baseURI, "services: the URL") : href, {
    headers: r?.headers,
    credentials: r?.credentials ?? "omit",
    signal: options.signal,
  });
  if (!res.ok) throw new Error(`mbmap: services: HTTP ${res.status} for ${href}`);
  const tooLarge = () => new Error(`mbmap: services: ${href} is larger than ${MAX_DOCUMENT_BYTES} bytes`);
  if (!res.body) return res.text();
  if (Number(res.headers.get("content-length")) > MAX_DOCUMENT_BYTES) {
    await res.body.cancel();
    throw tooLarge();
  }
  const reader = res.body.getReader();
  const parts: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_DOCUMENT_BYTES) {
      await reader.cancel();
      throw tooLarge();
    }
    parts.push(value);
  }
  const bytes = new Uint8Array(size);
  let at = 0;
  for (const p of parts) bytes.set(p, (at += p.byteLength) - p.byteLength);
  return new TextDecoder().decode(bytes);
}

async function loadJSON(url: string, options: ServiceOptions): Promise<unknown> {
  const text = await load(url, options);
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`mbmap: services: ${url} is not JSON`);
  }
}

/**
 * Fetches and reads a service's capabilities: `url` is the service endpoint (`SERVICE` and
 * `REQUEST=GetCapabilities` are added) or a capabilities document (a URL ending in `.xml`).
 */
export async function getCapabilities(url: string, service: "WMS", options?: ServiceOptions): Promise<WMSCapabilities>;
export async function getCapabilities(url: string, service: "WMTS", options?: ServiceOptions): Promise<WMTSCapabilities>;
export async function getCapabilities(url: string, service: "WFS", options?: ServiceOptions): Promise<WFSCapabilities>;
export async function getCapabilities(url: string, service: "WMS" | "WMTS" | "WFS", options: ServiceOptions = {}): Promise<WMSCapabilities | WMTSCapabilities | WFSCapabilities> {
  const doc = /\.xml([?#]|$)/i.test(url) ? url : withQuery(url, { SERVICE: service, REQUEST: "GetCapabilities" });
  const xml = await load(doc, options);
  const base = httpUrl(doc, document.baseURI, "services: the URL");
  return service === "WMS" ? readWMSCapabilities(xml, base) : service === "WMTS" ? readWMTSCapabilities(xml, base) : readWFSCapabilities(xml, base);
}

/** Fetches an ArcGIS REST service's (or layer's) `?f=json`; an `error` it answers with throws. */
export async function arcgisService(url: string, options: ServiceOptions = {}): Promise<ArcGISService> {
  const json = await loadJSON(withQuery(url, { f: "json" }), options);
  if (json === null || typeof json !== "object" || Array.isArray(json)) throw new Error("mbmap: services: not an ArcGIS service description");
  const error = (json as { error?: { code?: number; message?: string } }).error;
  if (error) throw new Error(`mbmap: services: ArcGIS error ${error.code ?? ""}: ${error.message ?? ""}`);
  return json as ArcGISService;
}

/** Fetches the collections of the OGC API at `url` (its landing page, whose `data` link is followed). */
export async function ogcCollections(url: string, options: ServiceOptions = {}): Promise<OGCCollection[]> {
  const landing = withQuery(url, { f: "json" });
  const data = ogcLink(ogcLinks(await loadJSON(landing, options), landing), ["data"], /json/) ?? withQuery(`${url.replace(/[?#].*$/, "").replace(/\/+$/, "")}/collections`, { f: "json" });
  return readOGCCollections(await loadJSON(data, options), data);
}

/** Fetches one collection of an OGC API (`url`: `/collections/{id}`). */
export async function ogcCollection(url: string, options: ServiceOptions = {}): Promise<OGCCollection> {
  const doc = withQuery(url, { f: "json" });
  return readOGCCollection(await loadJSON(doc, options), doc);
}

/** A source for a collection's vector or map tiles on WebMercatorQuad (OGC API - Tiles). */
export async function ogcTiles(collection: OGCCollection, kind: "vector" | "map", options: ServiceOptions = {}): Promise<TileSource> {
  const list = kind === "vector" ? collection.vectorTilesUrl : collection.mapTilesUrl;
  if (!list) throw new Error(`mbmap: services: the collection ${collection.id} has no ${kind} tiles`);
  const tileset = ogcTilesetUrl(await loadJSON(list, options), list);
  if (!tileset) throw new Error(`mbmap: services: the collection ${collection.id} has no ${kind} tiles on WebMercatorQuad`);
  return ogcTileSource(await loadJSON(tileset, options), tileset);
}
