import { type Bounds, clampBounds, clickWindow, epsgCode, type ImageRequest, isWebMercator, lngLatToMercator, northFirst, type ReprojectedSource, resolved, type TileSource, validBounds, withQuery, zoomResolution } from "./common.ts";
import { geojsonFormat } from "./features.ts";
import { at, children, first, href, optional, parseXml, text, texts } from "./xml.ts";

/** A layer style; `legendUrl` the first LegendURL's. */
export interface WMSStyle {
  name: string;
  title: string;
  legendUrl?: string;
}

/**
 * A WMS layer, inheriting as WMS 1.3.0 §7.2.4.8 says. `crs` holds 1.1.1's SRS; `bounds` is the EX_Geographic- (1.1.1: LatLon-)
 * BoundingBox; `boundingBoxes` as written (1.3.0 axis order); `minScale`/`maxScale` denominators (1.1.1's ScaleHint as ogc-client).
 */
export interface WMSLayer {
  name?: string;
  title: string;
  abstract?: string;
  crs: string[];
  bounds?: Bounds;
  boundingBoxes: { crs: string; bbox: [number, number, number, number] }[];
  styles: WMSStyle[];
  queryable: boolean;
  opaque: boolean;
  minScale?: number;
  maxScale?: number;
  attribution?: { title?: string; url?: string };
  layers: WMSLayer[];
}

/** What a WMS GetCapabilities document says; `getMapUrl` and `getFeatureInfoUrl` are the HTTP GET endpoints. */
export interface WMSCapabilities {
  service: "WMS";
  version: string;
  title: string;
  abstract?: string;
  getMapUrl: string;
  getFeatureInfoUrl?: string;
  mapFormats: string[];
  infoFormats: string[];
  layers: WMSLayer[];
}

const flag = (e: Element, name: string): boolean | undefined => {
  const v = e.getAttribute(name);
  return v === null || v === "" ? undefined : v === "1" || v === "true";
};

const decimal = (e: Element | null): number | undefined => {
  const t = text(e);
  return t === "" ? undefined : Number(t);
};

// ScaleHint gives the diagonal of a pixel in meters; its scale denominator as ogc-client reckons it.
const fromHint = (v: string | null): number | undefined =>
  v === null || v === "" ? undefined : Math.sqrt(0.5 * Number(v) ** 2) / 0.00028;

function readLayer(e: Element, v13: boolean, parent: WMSLayer | null): WMSLayer {
  const geo = first(e, v13 ? "EX_GeographicBoundingBox" : "LatLonBoundingBox");
  const ownBounds = geo
    ? v13
      ? (["westBoundLongitude", "southBoundLatitude", "eastBoundLongitude", "northBoundLatitude"].map((n) => decimal(first(geo, n))) as number[])
      : ["minx", "miny", "maxx", "maxy"].map((n) => Number(geo.getAttribute(n)))
    : undefined;
  const crsKey = v13 ? "CRS" : "SRS";
  const boxes = children(e, "BoundingBox").map((b) => ({
    crs: b.getAttribute(crsKey) ?? "",
    bbox: ["minx", "miny", "maxx", "maxy"].map((n) => Number(b.getAttribute(n))) as [number, number, number, number],
  }));
  const hint = v13 ? null : first(e, "ScaleHint");
  const attribution = first(e, "Attribution");
  const layer: WMSLayer = {
    name: optional(e, "Name"),
    title: text(first(e, "Title")),
    abstract: optional(e, "Abstract"),
    crs: [...texts(e, crsKey), ...(parent?.crs ?? [])],
    bounds: ownBounds ? validBounds(ownBounds) : parent?.bounds,
    boundingBoxes: boxes.length ? boxes : (parent?.boundingBoxes ?? []),
    styles: [
      ...children(e, "Style").map((s) => ({
        name: text(first(s, "Name")),
        title: text(first(s, "Title")),
        legendUrl: href(at(s, "LegendURL", "OnlineResource")),
      })),
      ...(parent?.styles ?? []),
    ],
    queryable: flag(e, "queryable") ?? parent?.queryable ?? false,
    opaque: flag(e, "opaque") ?? parent?.opaque ?? false,
    minScale: (v13 ? decimal(first(e, "MinScaleDenominator")) : fromHint(hint?.getAttribute("min") ?? null)) ?? (hint || !parent ? undefined : parent.minScale),
    maxScale: (v13 ? decimal(first(e, "MaxScaleDenominator")) : fromHint(hint?.getAttribute("max") ?? null)) ?? (hint || !parent ? undefined : parent.maxScale),
    attribution: attribution ? { title: optional(attribution, "Title"), url: href(first(attribution, "OnlineResource")) } : parent?.attribution,
    layers: [],
  };
  layer.layers = children(e, "Layer").map((child) => readLayer(child, v13, layer));
  return layer;
}

const getUrl = (operation: Element | null): string | undefined => href(at(operation, "DCPType", "HTTP", "Get", "OnlineResource"));

/** Reads a WMS 1.1.1 or 1.3.0 GetCapabilities document; `base`: its URL, which relative URLs in it are resolved against. */
export function readWMSCapabilities(xml: string | Document, base?: string): WMSCapabilities {
  const root = parseXml(xml, "WMS capabilities");
  const version = root.getAttribute("version") ?? "";
  if (!/^(WMS_Capabilities|WMT_MS_Capabilities)$/.test(root.localName)) throw new Error("mbmap: services: not a WMS capabilities document");
  const v13 = !version.startsWith("1.1");
  const capability = first(root, "Capability");
  const request = first(capability, "Request");
  const getMap = first(request, "GetMap");
  const info = first(request, "GetFeatureInfo");
  const service = first(root, "Service");
  const getMapUrl = getUrl(getMap);
  const infoUrl = getUrl(info);
  if (!getMapUrl) throw new Error("mbmap: services: the WMS capabilities have no GetMap URL");
  return {
    service: "WMS",
    version,
    title: text(first(service, "Title")),
    abstract: optional(service, "Abstract"),
    getMapUrl: resolved(getMapUrl, base),
    getFeatureInfoUrl: infoUrl && resolved(infoUrl, base),
    mapFormats: texts(getMap, "Format"),
    infoFormats: texts(info, "Format"),
    layers: children(capability, "Layer").map((l) => readLayer(l, v13, null)),
  };
}

/** Every layer of `layers` and their sublayers, depth first. */
export function allLayers<T extends { layers: T[] }>(layers: T[]): T[] {
  return layers.flatMap((l) => [l, ...allLayers(l.layers)]);
}

/**
 * `layers`: the names to draw, bottom first; `styles` theirs (default the server's); `format` (default `image/png`);
 * `transparent` (default true); `tileSize` (default 256); `crs`: the CRS a `reprojected` `wmsSource` asks in; `params`:
 * more GetMap parameters, such as a dimension's `TIME`.
 */
export interface WMSSourceOptions {
  layers: string | string[];
  crs?: string;
  styles?: string | string[];
  format?: string;
  transparent?: boolean;
  tileSize?: number;
  params?: Record<string, string | number>;
}

/** The layers `options` names (each offering `crs`, by default EPSG:3857), the GetMap parameters but size and BBOX, and the CRS key. */
function getMap(capabilities: WMSCapabilities, options: WMSSourceOptions, crs?: string) {
  const names = typeof options.layers === "string" ? [options.layers] : options.layers;
  const all = allLayers(capabilities.layers);
  const offers = (l: WMSLayer) => (crs === undefined ? l.crs.some(isWebMercator) : l.crs.some((c) => c.toUpperCase() === crs.toUpperCase()));
  const layers = names.map((name) => {
    const layer = all.find((l) => l.name === name);
    if (!layer) throw new Error(`mbmap: services: the WMS has no layer named ${name}`);
    if (!offers(layer)) throw new Error(`mbmap: services: the WMS layer ${name} is not offered in ${crs ?? "EPSG:3857"}`);
    return layer;
  });
  const v13 = !capabilities.version.startsWith("1.1");
  const code = crs ?? layers[0].crs.find((c) => c.toUpperCase() === "EPSG:3857") ?? layers[0].crs.find(isWebMercator)!;
  const params = {
    SERVICE: "WMS",
    VERSION: capabilities.version,
    REQUEST: "GetMap",
    LAYERS: names.join(","),
    STYLES: typeof options.styles === "string" ? options.styles : (options.styles ?? []).join(","),
    FORMAT: options.format ?? "image/png",
    TRANSPARENT: options.transparent === false ? "FALSE" : "TRUE",
  };
  return { layers, names, params, v13, crs: { [v13 ? "CRS" : "SRS"]: code } };
}

/**
 * A raster source drawing `options.layers` of a WMS by GetMap requests in EPSG:3857, one per tile, with the layers' geographic
 * bounds and attribution. Layers without EPSG:3857 make a `reprojected` source instead, asked in `options.crs` (by default
 * EPSG:4326 if all offer it, else the first layer's first EPSG CRS that all offer) and drawn by mbmap/data's worker.
 */
export function wmsSource(capabilities: WMSCapabilities, options: WMSSourceOptions): TileSource | ReprojectedSource {
  const names = typeof options.layers === "string" ? [options.layers] : options.layers;
  const all = allLayers(capabilities.layers);
  const named = names.map((n) => all.find((l) => l.name === n));
  const mercator = named.every((l) => !l || l.crs.some(isWebMercator)) && options.crs === undefined;
  const common = (c: string) => named.every((l) => !l || l.crs.some((d) => d.toUpperCase() === c.toUpperCase()));
  const crs = mercator ? undefined : options.crs ?? (common("EPSG:4326") ? "EPSG:4326" : named[0]?.crs.find((c) => epsgCode(c) !== undefined && common(c)));
  if (!mercator && crs === undefined) throw new Error(`mbmap: services: the WMS layers ${names.join(",")} share no EPSG CRS`);
  const { layers, params, crs: crsParam, v13 } = getMap(capabilities, options, crs);
  const size = options.tileSize ?? 256;
  const bounds = layers.map((l) => l.bounds).filter((b) => b !== undefined);
  const titles = [...new Set(layers.map((l) => l.attribution?.title).filter((t) => t))];
  const extra = {
    ...(bounds.length === layers.length && {
      bounds: clampBounds([Math.min(...bounds.map((b) => b[0])), Math.min(...bounds.map((b) => b[1])), Math.max(...bounds.map((b) => b[2])), Math.max(...bounds.map((b) => b[3]))]),
    }),
    ...(titles.length && { attribution: titles.join(" | ") }),
  };
  if (crs !== undefined) {
    const code = epsgCode(crs);
    if (code === undefined) throw new Error(`mbmap: services: ${crs} is not an EPSG CRS`);
    const template = withQuery(capabilities.getMapUrl, { ...params, WIDTH: "{width}", HEIGHT: "{height}", ...crsParam, BBOX: "{bbox}", ...options.params });
    return { type: "reprojected", crs: code, image: { template, northFirst: v13 && northFirst(crs) }, ...extra };
  }
  const url = withQuery(capabilities.getMapUrl, { ...params, WIDTH: size, HEIGHT: size, ...crsParam, BBOX: "{bbox-epsg-3857}", ...options.params });
  return { type: "raster", tiles: [url], tileSize: size, ...extra };
}

/** GetMap requests for one image of `options.layers` (`tileSize` unused), as `followImage` asks for the view. */
export function wmsImage(capabilities: WMSCapabilities, options: WMSSourceOptions): ImageRequest {
  const { params, crs } = getMap(capabilities, options);
  return (bbox, width, height) => withQuery(capabilities.getMapUrl, { ...params, WIDTH: width, HEIGHT: height, ...crs, BBOX: bbox.join(","), ...options.params });
}

/**
 * `queryLayers` (default `layers`), `infoFormat` (default the first JSON format the service offers)
 * and `featureCount` of a GetFeatureInfo request; the rest as `WMSSourceOptions`.
 */
export interface WMSFeatureInfoOptions extends WMSSourceOptions {
  queryLayers?: string | string[];
  infoFormat?: string;
  featureCount?: number;
}

/**
 * The GetFeatureInfo request for `lngLat` on a map at `zoom`, as OpenLayers' `getFeatureInfoUrl` makes it: a 101 by 101
 * pixel window in EPSG:3857 around the point.
 */
export function wmsFeatureInfoUrl(capabilities: WMSCapabilities, options: WMSFeatureInfoOptions, lngLat: [number, number], zoom: number): string {
  if (!capabilities.getFeatureInfoUrl) throw new Error("mbmap: services: the WMS has no GetFeatureInfo");
  const { names, params, v13, crs } = getMap(capabilities, options);
  const format = options.infoFormat ?? geojsonFormat(capabilities.infoFormats);
  if (!format) throw new Error("mbmap: services: the WMS offers GetFeatureInfo in no JSON format");
  const [x, y] = lngLatToMercator(...lngLat);
  const resolution = zoomResolution(zoom);
  const bbox = clickWindow(x, y, resolution);
  const query = options.queryLayers ?? names;
  return withQuery(capabilities.getFeatureInfoUrl, {
    ...params,
    REQUEST: "GetFeatureInfo",
    QUERY_LAYERS: typeof query === "string" ? query : query.join(","),
    INFO_FORMAT: format,
    FEATURE_COUNT: options.featureCount,
    [v13 ? "I" : "X"]: Math.floor((x - bbox[0]) / resolution),
    [v13 ? "J" : "Y"]: Math.floor((bbox[3] - y) / resolution),
    WIDTH: 101,
    HEIGHT: 101,
    ...crs,
    BBOX: bbox.join(","),
    ...options.params,
  });
}
