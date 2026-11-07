// mbmap/services: reading GIS web services (OGC WMS, WMTS, WFS and OGC API; ArcGIS REST) into
// style sources. Requests go through `transformRequest` as the map's do; no credentials otherwise.
import { readOGCCollection, readOGCCollections, type OGCCollection, ogcTileSource, ogcTilesetUrl, ogcLink, ogcLinks } from "./services/ogcapi";
import { type ArcGISIdentifyOptions, arcgisIdentifyUrl, arcgisVectorStyle, type ArcGISService } from "./services/arcgis";

import { readWFSCapabilities, type WFSCapabilities } from "./services/wfs";
import { readWMSCapabilities, type WMSCapabilities, type WMSFeatureInfoOptions, wmsFeatureInfoUrl } from "./services/wms";
import { readWMTSCapabilities, type WMTSCapabilities } from "./services/wmts";
import { type Bounds, clampBounds, type ImageRequest, lngLatToMercator, mercatorToLngLat, type TileSource, withQuery, zoomResolution } from "./services/common";
import { arcgisFormat, arcgisQueryUrl, type ArcGISQueryOptions, type FeatureCollection, gather, geojsonFormat, gmlFormat, MAX_FEATURES, ogcItemsUrl, type OGCItemsOptions, pageFeatures, wfsFeatureUrl, type WFSFeatureOptions } from "./services/features";
import { parseXml } from "./services/xml";
import type { StyleSpecification } from "./style";
import { httpUrl, type TransformedRequest, wasmUrl } from "./urls";
import { WorkerClient } from "./worker-client";

export { arcgisBounds, arcgisIdentifyUrl, arcgisImage, arcgisSource, arcgisVectorStyle, arcgisZooms, type ArcGISIdentifyOptions, type ArcGISService, type ArcGISSourceOptions } from "./services/arcgis";
export { isWebMercator, resolved, withQuery, type Bounds, type ImageRequest, type TileSource } from "./services/common";
export { arcgisFormat, arcgisQueryUrl, geojsonFormat, gmlFormat, MAX_FEATURES, MAX_PAGES, ogcItemsUrl, wfsFeatureUrl, type ArcGISQueryOptions, type FeatureCollection, type OGCItemsOptions, type WFSFeatureOptions } from "./services/features";
export { isWebMercatorQuad, ogcLinks, ogcTileSource, ogcTilesetUrl, readOGCCollection, readOGCCollections, type OGCCollection, type OGCLink } from "./services/ogcapi";
export { readWFSCapabilities, type WFSCapabilities, type WFSFeatureType } from "./services/wfs";
export { allLayers, readWMSCapabilities, wmsFeatureInfoUrl, wmsImage, wmsSource, type WMSCapabilities, type WMSFeatureInfoOptions, type WMSLayer, type WMSSourceOptions, type WMSStyle } from "./services/wms";
export { mercatorZooms, readWMTSCapabilities, wmtsSource, type WMTSCapabilities, type WMTSLayer, type WMTSResource, type WMTSSourceOptions, type WMTSTileMatrix, type WMTSTileMatrixSet } from "./services/wmts";

/** The most a service document may weigh, in bytes. */
export const MAX_DOCUMENT_BYTES = 32 * 1024 * 1024;

/** `transformRequest`: as the map's (asked with `"Source"`); `signal`: aborts the requests. */
export interface ServiceOptions {
  transformRequest?: (url: string, type: "Source") => TransformedRequest | undefined;
  signal?: AbortSignal;
}

/** The bytes at `url` (http(s), resolved against the page), refused past `MAX_DOCUMENT_BYTES`. */
async function loadBytes(url: string, options: ServiceOptions, accept?: string): Promise<Uint8Array<ArrayBuffer>> {
  const href = httpUrl(url, document.baseURI, "services: the URL");
  const r = options.transformRequest?.(href, "Source");
  const res = await fetch(r ? httpUrl(r.url, document.baseURI, "services: the URL") : href, {
    headers: accept ? { accept, ...r?.headers } : r?.headers,
    credentials: r?.credentials ?? "omit",
    signal: options.signal,
  });
  if (!res.ok) throw new Error(`mbmap: services: HTTP ${res.status} for ${href}`);
  const tooLarge = () => new Error(`mbmap: services: ${href} is larger than ${MAX_DOCUMENT_BYTES} bytes`);
  if (!res.body) return new Uint8Array(await res.arrayBuffer());
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
  return bytes;
}

/** The text at `url`, as `loadBytes`. */
async function load(url: string, options: ServiceOptions, accept?: string): Promise<string> {
  return new TextDecoder().decode(await loadBytes(url, options, accept));
}

async function loadJSON(url: string, options: ServiceOptions, accept?: string): Promise<unknown> {
  const text = await load(url, options, accept);
  try {
    return JSON.parse(text);
  } catch {
    // An OGC service reports a refused request as an XML exception report.
    if (text.trimStart().startsWith("<")) parseXml(text, url);
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

/**
 * Fetches an ArcGIS VectorTileServer's style with its URLs made absolute (`arcgisVectorStyle`):
 * `options.style` names another style of the service's (default its `defaultStyles` root.json).
 */
export async function arcgisStyle(url: string, options: ServiceOptions & { style?: string } = {}): Promise<StyleSpecification> {
  const absolute = httpUrl(url, document.baseURI, "services: the URL").replace(/[?#].*$/, "").replace(/\/+$/, "");
  const service = await arcgisService(absolute, options);
  const styleUrl = httpUrl(options.style ?? `${service.defaultStyles ?? "resources/styles"}/root.json`, `${absolute}/`, "services: the style");
  const style = await loadJSON(styleUrl, options);
  if (style === null || typeof style !== "object" || (style as { version?: unknown }).version !== 8) throw new Error("mbmap: services: not a version 8 style");
  return arcgisVectorStyle(style as StyleSpecification, styleUrl, service, absolute);
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

/** `maxFeatures`: the most to gather across pages (default and cap `MAX_FEATURES`); the rest as `ServiceOptions`. */
export interface FeatureOptions extends ServiceOptions {
  maxFeatures?: number;
}

const GEOJSON_ACCEPT = "application/geo+json, application/json;q=0.9";

const most = (options: FeatureOptions): number => Math.min(options.maxFeatures ?? MAX_FEATURES, MAX_FEATURES);

/**
 * A collection's features from OGC API - Features (`collection`, or its items URL), following each
 * page's `next` link.
 */
export async function ogcFeatures(collection: OGCCollection | string, options: OGCItemsOptions & FeatureOptions = {}): Promise<FeatureCollection> {
  const items = typeof collection === "string" ? collection : collection.itemsUrl;
  if (!items) throw new Error(`mbmap: services: the collection ${(collection as OGCCollection).id} has no items`);
  const first = ogcItemsUrl(httpUrl(items, document.baseURI, "services: the URL"), options);
  return gather(first, (url) => loadJSON(url, options, GEOJSON_ACCEPT), (page, url) => ogcLink(ogcLinks(page, url), ["next"], /json/), most(options), "OGC API items");
}

/**
 * A WFS feature type's features as GeoJSON (the service must offer a GeoJSON output format).
 * With `count` on WFS 2.0, pages by STARTINDEX until a page comes back short.
 */
export async function wfsFeatures(capabilities: WFSCapabilities, options: WFSFeatureOptions & FeatureOptions): Promise<FeatureCollection> {
  const type = capabilities.featureTypes.find((t) => t.name === options.typeName);
  if (!type) throw new Error(`mbmap: services: the WFS has no feature type ${options.typeName}`);
  if (!capabilities.getFeatureUrl) throw new Error("mbmap: services: the WFS capabilities have no GetFeature URL");
  const formats = type.outputFormats.length ? type.outputFormats : capabilities.outputFormats;
  const outputFormat = options.outputFormat ?? geojsonFormat(formats) ?? gmlFormat(formats);
  const gml = outputFormat === undefined || !/json/i.test(outputFormat);
  // GML is read in EPSG:4326 only: asked for as such, latitude first but in WFS 1.0.
  const v10 = capabilities.version.startsWith("1.0");
  const crs = options.crs ?? (gml ? (v10 ? "EPSG:4326" : "urn:ogc:def:crs:EPSG::4326") : undefined);
  const paged = options.count !== undefined && capabilities.version.startsWith("2.");
  const url = (startIndex: number) => wfsFeatureUrl(capabilities.getFeatureUrl!, capabilities.version, {
    ...options,
    outputFormat,
    crs,
    startIndex: (options.startIndex ?? 0) + startIndex,
    count: options.count ?? options.maxFeatures,
  });
  // Under a bare `EPSG:4326` the server writes the axis order of what it was asked for. The GML reader is a file of its own.
  const read = async (u: string) => {
    if (!gml) return loadJSON(u, options);
    const [text, m] = await Promise.all([load(u, options), import("./services/gml")]);
    return m.readGml(text, m.srsNorthFirst(crs ?? "", false));
  };
  return gather(url(0), read, (page, _, n) => (paged && n % options.count! === 0 ? url(n) : undefined), most(options), "WFS GetFeature");
}

/**
 * `format`: `"geojson"` (ArcGIS Server 10.4 and later), or `"json"` or `"pbf"` read by services.wasm in its own
 * worker; by default as `arcgisFormat`. `workerUrl`, `wasmUrl`: where they are served (default: beside this module).
 */
export interface ArcGISFeatureOptions extends ArcGISQueryOptions, FeatureOptions, WorkerOptions {
  format?: "geojson" | "json" | "pbf";
}

/** Where the worker reading Esri's formats (`workerUrl`) and its wasm (`wasmUrl`) are served; by default beside this module. */
export interface WorkerOptions {
  workerUrl?: string | URL;
  wasmUrl?: string | URL;
}

const esriClient = new WorkerClient("services");

/** A page of an ArcGIS query in `format` ("json" or "pbf") read by services.wasm, as its GeoJSON would be. */
async function loadEsri(url: string, format: "json" | "pbf", options: ArcGISFeatureOptions): Promise<unknown> {
  return readEsri(await loadBytes(url, options), format, options);
}

/** An ArcGIS query result's bytes read by services.wasm, as its GeoJSON would be. */
async function readEsri(bytes: Uint8Array<ArrayBuffer>, format: "json" | "pbf", options: WorkerOptions): Promise<FeatureCollection & { exceededTransferLimit: boolean }> {
  esriClient.start(options.workerUrl ?? new URL("./services-worker.js", import.meta.url), (page) => ({
    wasm: wasmUrl(options.wasmUrl ?? new URL("./services.wasm", import.meta.url), page),
  }));
  // A server refuses a query with a JSON error whatever the format asked.
  const as = bytes[0] === 0x7b ? "json" : format;
  const { features, exceeded } = await esriClient.call<{ features: unknown[]; exceeded: boolean }>("esri", { bytes: bytes.buffer, format: as }, [bytes.buffer]);
  return { type: "FeatureCollection", features, exceededTransferLimit: exceeded };
}

/**
 * An ArcGIS FeatureServer or MapServer layer's features as GeoJSON, in the layer's best format
 * (`ArcGISFeatureOptions`), paged by `resultOffset` while the layer supports it and answers
 * `exceededTransferLimit`.
 */
export async function arcgisFeatures(layerUrl: string, options: ArcGISFeatureOptions = {}): Promise<FeatureCollection> {
  const url = httpUrl(layerUrl, document.baseURI, "services: the URL");
  const layer = await arcgisService(url, options);
  const format = options.format ?? arcgisFormat(layer);
  const paging = (layer as { advancedQueryCapabilities?: { supportsPagination?: boolean } }).advancedQueryCapabilities?.supportsPagination === true;
  const count = options.count ?? (paging ? layer.maxRecordCount : undefined);
  const page = (offset: number) =>
    arcgisQueryUrl(url, { ...options, offset: paging ? (options.offset ?? 0) + offset : options.offset, count: paging ? count : options.count }, format);
  const more = (p: unknown) => {
    const r = p as { exceededTransferLimit?: boolean; properties?: { exceededTransferLimit?: boolean } };
    return r.exceededTransferLimit === true || r.properties?.exceededTransferLimit === true;
  };
  const read = (u: string) => (format === "geojson" ? loadJSON(u, options) : loadEsri(u, format, options));
  return gather(page(0), read, (p, _, n) => (paging && more(p) ? page(n) : undefined), most(options), "ArcGIS query");
}

/** Stops the worker that reads ArcGIS `f=json` and `f=pbf` (`arcgisFeatures`); pending reads reject. */
export function terminate(): void {
  esriClient.terminate();
}

/**
 * The features a WMS's GetFeatureInfo gives at `lngLat` on a map at `zoom` (`wmsFeatureInfoUrl`), in a JSON
 * format; a server's exception report throws with its message.
 */
export async function wmsFeatureInfo(
  capabilities: WMSCapabilities,
  options: WMSFeatureInfoOptions,
  lngLat: [number, number],
  zoom: number,
  serviceOptions: ServiceOptions = {},
): Promise<FeatureCollection> {
  const url = wmsFeatureInfoUrl(capabilities, options, lngLat, zoom);
  return { type: "FeatureCollection", features: pageFeatures(await loadJSON(url, serviceOptions), "WMS GetFeatureInfo") };
}

/**
 * The features a MapServer's `identify` finds at `lngLat` on a map at `zoom` (`arcgisIdentifyUrl`), as GeoJSON in
 * EPSG:4326 read by services.wasm; each feature's `layer` names the layer it was found in (`id`, `name`).
 */
export async function arcgisIdentify(
  url: string,
  lngLat: [number, number],
  zoom: number,
  options: ArcGISIdentifyOptions & ServiceOptions & WorkerOptions = {},
): Promise<FeatureCollection> {
  const doc = (await loadJSON(arcgisIdentifyUrl(httpUrl(url, document.baseURI, "services: the URL"), lngLat, zoom, options), options)) as {
    results?: { layerId?: number; layerName?: string; attributes?: unknown; geometry?: unknown }[];
    error?: unknown;
  };
  const results = Array.isArray(doc?.results) ? doc.results : [];
  const set = doc?.error ? doc : { features: results.map((r) => ({ attributes: r.attributes, geometry: r.geometry })) };
  const { features } = await readEsri(new TextEncoder().encode(JSON.stringify(set)), "json", options);
  return { type: "FeatureCollection", features: features.map((f, i) => ({ ...(f as object), layer: { id: results[i].layerId, name: results[i].layerName } })) };
}

/** What `followView` needs of a map: mbmap's `Map` or MapLibre's. */
export interface ViewMap {
  getBounds(): { getWest(): number; getSouth(): number; getEast(): number; getNorth(): number } | { west: number; south: number; east: number; north: number };
  getZoom(): number;
  on(type: "moveend", listener: () => void): unknown;
  off(type: "moveend", listener: () => void): unknown;
  getSource(id: string): unknown;
}

/** `minzoom`: below it the source is emptied and nothing is asked; `onError` gets failed queries (default `console.error`). */
export interface FollowOptions {
  minzoom?: number;
  onError?: (error: unknown) => void;
}

const EMPTY: FeatureCollection = { type: "FeatureCollection", features: [] };

/** What `map` shows, in degrees within the world's. */
function viewBounds(map: ViewMap): Bounds {
  const b = map.getBounds() as { west?: number; south?: number; east?: number; north?: number; getWest?: () => number; getSouth?: () => number; getEast?: () => number; getNorth?: () => number };
  return clampBounds(b.getWest ? [b.getWest(), b.getSouth!(), b.getEast!(), b.getNorth!()] : [b.west!, b.south!, b.east!, b.north!]);
}

/**
 * Keeps GeoJSON source `sourceId` filled with `query(bounds, signal)` for what the map shows: asked
 * again after each move, the previous query aborted. Returns the function that stops it.
 */
export function followView(
  map: ViewMap,
  sourceId: string,
  query: (bounds: Bounds, signal: AbortSignal) => Promise<FeatureCollection>,
  options: FollowOptions = {},
): () => void {
  let current: AbortController | null = null;
  const set = (data: FeatureCollection) => (map.getSource(sourceId) as { setData?: (d: unknown) => void } | undefined)?.setData?.(data);
  const update = () => {
    current?.abort();
    current = null;
    if (map.getZoom() < (options.minzoom ?? 0)) return set(EMPTY);
    const clamped = viewBounds(map);
    const controller = (current = new AbortController());
    query(clamped, controller.signal).then(
      (data) => controller === current && set(data),
      (e) => controller.signal.aborted || (options.onError ?? console.error)(e),
    );
  };
  map.on("moveend", update);
  update();
  return () => {
    current?.abort();
    map.off("moveend", update);
  };
}

/** What `followImage` needs of a map besides `ViewMap`'s: adding the image source. */
export interface ImageMap extends ViewMap {
  addSource(id: string, source: { type: "image"; url: string; coordinates: number[][] }): unknown;
}

/** `pixelRatio`: device pixels per CSS pixel asked for (default `devicePixelRatio`); `maxSize`: the most pixels on a side (default 4096). */
export interface FollowImageOptions {
  pixelRatio?: number;
  maxSize?: number;
}

/**
 * Keeps image source `sourceId` (added unless the map has it) showing one image of what the map shows, as
 * OpenLayers' `ImageWMS` and `ImageArcGISRest` do: `image` (`wmsImage`, `arcgisImage`) asked again after each
 * move for the view's EPSG:3857 box at its resolution. Returns the function that stops it.
 */
export function followImage(map: ImageMap, sourceId: string, image: ImageRequest, options: FollowImageOptions = {}): () => void {
  const update = () => {
    const [w, s, e, n] = viewBounds(map);
    const lat = (v: number) => Math.min(Math.max(v, -85.051129), 85.051129);
    const [x0, y0] = lngLatToMercator(w, lat(s));
    const [x1, y1] = lngLatToMercator(e, lat(n));
    const ratio = options.pixelRatio ?? globalThis.devicePixelRatio ?? 1;
    const scale = Math.min(ratio / zoomResolution(map.getZoom()), (options.maxSize ?? 4096) / Math.max(x1 - x0, y1 - y0));
    const width = Math.max(1, Math.round((x1 - x0) * scale));
    const height = Math.max(1, Math.round((y1 - y0) * scale));
    const url = image([x0, y0, x1, y1], width, height, ratio);
    const [west, south] = mercatorToLngLat(x0, y0);
    const [east, north] = mercatorToLngLat(x1, y1);
    const coordinates = [[west, north], [east, north], [east, south], [west, south]];
    const source = map.getSource(sourceId) as { updateImage?: (o: { url: string; coordinates: number[][] }) => unknown } | undefined;
    if (source) source.updateImage?.({ url, coordinates });
    else map.addSource(sourceId, { type: "image", url, coordinates });
  };
  map.on("moveend", update);
  update();
  return () => map.off("moveend", update);
}
