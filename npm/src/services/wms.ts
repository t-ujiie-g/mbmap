import { type Bounds, clampBounds, isWebMercator, resolved, type TileSource, validBounds, withQuery } from "./common.ts";
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
 * `layers`: the names to draw, bottom first; `styles` theirs (default the server's); `format`
 * (default `image/png`); `transparent` (default true); `tileSize` (default 256); `params`: more
 * GetMap parameters, such as a dimension's `TIME`.
 */
export interface WMSSourceOptions {
  layers: string | string[];
  styles?: string | string[];
  format?: string;
  transparent?: boolean;
  tileSize?: number;
  params?: Record<string, string | number>;
}

/**
 * A raster source drawing `options.layers` of a WMS by GetMap requests in EPSG:3857, one per tile,
 * with the layers' geographic bounds and attribution. The layers must offer EPSG:3857.
 */
export function wmsSource(capabilities: WMSCapabilities, options: WMSSourceOptions): TileSource {
  const names = typeof options.layers === "string" ? [options.layers] : options.layers;
  const all = allLayers(capabilities.layers);
  const layers = names.map((name) => {
    const layer = all.find((l) => l.name === name);
    if (!layer) throw new Error(`mbmap: services: the WMS has no layer named ${name}`);
    if (!layer.crs.some(isWebMercator)) throw new Error(`mbmap: services: the WMS layer ${name} is not offered in EPSG:3857`);
    return layer;
  });
  const v13 = !capabilities.version.startsWith("1.1");
  const size = options.tileSize ?? 256;
  const crs = layers[0].crs.find((c) => c.toUpperCase() === "EPSG:3857") ?? layers[0].crs.find(isWebMercator)!;
  const url = withQuery(capabilities.getMapUrl, {
    SERVICE: "WMS",
    VERSION: capabilities.version,
    REQUEST: "GetMap",
    LAYERS: names.join(","),
    STYLES: typeof options.styles === "string" ? options.styles : (options.styles ?? []).join(","),
    FORMAT: options.format ?? "image/png",
    TRANSPARENT: options.transparent === false ? "FALSE" : "TRUE",
    WIDTH: size,
    HEIGHT: size,
    [v13 ? "CRS" : "SRS"]: crs,
    BBOX: "{bbox-epsg-3857}",
    ...options.params,
  });
  const bounds = layers.map((l) => l.bounds).filter((b) => b !== undefined);
  const titles = [...new Set(layers.map((l) => l.attribution?.title).filter((t) => t))];
  return {
    type: "raster",
    tiles: [url],
    tileSize: size,
    ...(bounds.length === layers.length && {
      bounds: clampBounds([Math.min(...bounds.map((b) => b[0])), Math.min(...bounds.map((b) => b[1])), Math.max(...bounds.map((b) => b[2])), Math.max(...bounds.map((b) => b[3]))]),
    }),
    ...(titles.length && { attribution: titles.join(" | ") }),
  };
}
