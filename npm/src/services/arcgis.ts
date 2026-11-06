import { type Bounds, clampBounds, isWebMercator, mercatorToLngLat, mercatorZoom, MERCATOR_HALF, type TileSource, validBounds, withQuery } from "./common.ts";

/** The parts of an ArcGIS REST service's `?f=json` that mbmap reads; the rest is kept as given. */
export interface ArcGISService {
  serviceDescription?: string;
  description?: string;
  mapName?: string;
  name?: string;
  copyrightText?: string;
  capabilities?: string;
  singleFusedMapCache?: boolean;
  spatialReference?: { wkid?: number; latestWkid?: number };
  fullExtent?: { xmin: number; ymin: number; xmax: number; ymax: number; spatialReference?: { wkid?: number; latestWkid?: number } };
  tileInfo?: {
    rows: number;
    cols: number;
    format?: string;
    origin: { x: number; y: number };
    spatialReference?: { wkid?: number; latestWkid?: number };
    lods: { level: number; resolution: number; scale: number }[];
  };
  layers?: { id: number; name: string; parentLayerId?: number; subLayerIds?: number[] | null; defaultVisibility?: boolean; minScale?: number; maxScale?: number; type?: string; geometryType?: string }[];
  maxRecordCount?: number;
  [key: string]: unknown;
}

const wkid = (sr: { wkid?: number; latestWkid?: number } | undefined): number | undefined => sr?.latestWkid ?? sr?.wkid;

/** The service's `fullExtent` in degrees, when it is in Web Mercator or WGS 84. */
export function arcgisBounds(service: ArcGISService): Bounds | undefined {
  const e = service.fullExtent;
  if (!e) return undefined;
  const sr = wkid(e.spatialReference ?? service.spatialReference);
  if (sr === 4326) return validBounds([e.xmin, e.ymin, e.xmax, e.ymax]);
  if (!isWebMercator(sr)) return undefined;
  const clamp = (v: number) => Math.max(-MERCATOR_HALF, Math.min(MERCATOR_HALF, v));
  return validBounds([...mercatorToLngLat(clamp(e.xmin), clamp(e.ymin)), ...mercatorToLngLat(clamp(e.xmax), clamp(e.ymax))]);
}

/** The zooms of a cache in Web Mercator's quadtree (each level its zoom, the EPSG:3857 square), or null. */
export function arcgisZooms(service: ArcGISService): [number, number] | null {
  const t = service.tileInfo;
  if (!t || !isWebMercator(wkid(t.spatialReference ?? service.spatialReference)) || t.rows !== t.cols || !t.lods?.length) return null;
  if (Math.abs(t.origin.x + MERCATOR_HALF) > 1 || Math.abs(t.origin.y - MERCATOR_HALF) > 1) return null;
  if (!t.lods.every((l) => mercatorZoom(l.resolution, t.rows) === l.level)) return null;
  const levels = t.lods.map((l) => l.level);
  return [Math.min(...levels), Math.max(...levels)];
}

/**
 * `layers`: the sublayer ids to draw (a MapServer's `show:`), which needs `export`; `dynamic`:
 * `export` even from a cached service; `format` (default `png32`), `transparent` (default true),
 * `dpi` (default 96) and `tileSize` (default 256) for `export`; `params`: more `export` parameters.
 */
export interface ArcGISSourceOptions {
  layers?: number[];
  dynamic?: boolean;
  format?: string;
  transparent?: boolean;
  dpi?: number;
  tileSize?: number;
  params?: Record<string, string | number>;
}

/**
 * A raster source for an ArcGIS MapServer or ImageServer at `url` with its `?f=json` `service`:
 * its cache (`tile/{z}/{y}/{x}`) when it is in Web Mercator's quadtree, else an `export` (or
 * ImageServer `exportImage`) per tile in EPSG:3857.
 */
export function arcgisSource(service: ArcGISService, url: string, options: ArcGISSourceOptions = {}): TileSource {
  const base = url.replace(/[?#].*$/, "").replace(/\/+$/, "");
  const kind = /\/(MapServer|ImageServer)$/i.exec(base)?.[1].toLowerCase();
  if (!kind) throw new Error("mbmap: services: the URL is not an ArcGIS MapServer or ImageServer");
  const bounds = arcgisBounds(service);
  const extra = { ...(bounds && { bounds: clampBounds(bounds) }), ...(service.copyrightText && { attribution: service.copyrightText }) };
  const zooms = arcgisZooms(service);
  if (zooms && !options.layers && !options.dynamic && (service.singleFusedMapCache || kind === "imageserver")) {
    return { type: "raster", tiles: [`${base}/tile/{z}/{y}/{x}`], tileSize: service.tileInfo!.rows, minzoom: zooms[0], maxzoom: zooms[1], ...extra };
  }
  const size = options.tileSize ?? 256;
  const image = kind === "imageserver";
  const tiles = withQuery(`${base}/${image ? "exportImage" : "export"}`, {
    bbox: "{bbox-epsg-3857}",
    bboxSR: 3857,
    imageSR: 3857,
    size: `${size},${size}`,
    ...(!image && { dpi: options.dpi ?? 96 }),
    format: options.format ?? (image ? "png" : "png32"),
    transparent: options.transparent === false ? "false" : "true",
    ...(options.layers && { layers: `show:${options.layers.join(",")}` }),
    f: "image",
    ...options.params,
  });
  return { type: "raster", tiles: [tiles], tileSize: size, ...extra };
}
