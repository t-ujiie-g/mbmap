import { type Bounds, clampBounds, epsgCode, isWebMercator, MERCATOR_HALF, mercatorZoom, metersPerUnit, northFirst, OGC_PIXEL_METERS, REPROJECTED_TILE_SIZE, type ReprojectedSource, resolved, type TileSource, validBounds, withQuery, zoomForResolution, zoomTemplate } from "./common.ts";
import { at, children, corners, first, href, numbers, optional, parseXml, text, texts } from "./xml.ts";

/** A tile matrix: `topLeft` as written (in the CRS's axis order). */
export interface WMTSTileMatrix {
  id: string;
  scale: number;
  topLeft: [number, number];
  tileWidth: number;
  tileHeight: number;
  matrixWidth: number;
  matrixHeight: number;
}

export interface WMTSTileMatrixSet {
  id: string;
  crs: string;
  wellKnownScaleSet?: string;
  matrices: WMTSTileMatrix[];
}

/** A ResourceURL: `template` with WMTS's `{TileMatrix}`, `{TileRow}`, `{TileCol}`, `{Style}` and dimensions. */
export interface WMTSResource {
  format: string;
  resourceType: string;
  template: string;
}

/** A WMTS layer: `bounds` from its WGS84BoundingBox, `dimensions` with their defaults. */
export interface WMTSLayer {
  id: string;
  title: string;
  abstract?: string;
  bounds?: Bounds;
  styles: { id: string; title?: string; isDefault: boolean; legendUrl?: string }[];
  formats: string[];
  infoFormats: string[];
  tileMatrixSets: string[];
  resources: WMTSResource[];
  dimensions: { id: string; default: string; values: string[] }[];
}

/** What a WMTS 1.0.0 GetCapabilities document says; `getTileUrl` is the KVP endpoint, when it has one. */
export interface WMTSCapabilities {
  service: "WMTS";
  version: string;
  title: string;
  getTileUrl?: string;
  layers: WMTSLayer[];
  tileMatrixSets: WMTSTileMatrixSet[];
}

const boxBounds = (box: Element | null): Bounds | undefined => (box ? validBounds(corners(box)) : undefined);

/** Reads a WMTS 1.0.0 GetCapabilities document; `base`: its URL, which relative URLs in it are resolved against. */
export function readWMTSCapabilities(xml: string | Document, base?: string): WMTSCapabilities {
  const root = parseXml(xml, "WMTS capabilities");
  if (root.localName !== "Capabilities") throw new Error("mbmap: services: not a WMTS capabilities document");
  const contents = first(root, "Contents");
  const getTile = children(first(root, "OperationsMetadata"), "Operation").find((o) => o.getAttribute("name") === "GetTile");
  const kvp = children(at(getTile, "DCP", "HTTP"), "Get").find((g) => {
    const encodings = children(first(g, "Constraint"), "AllowedValues").flatMap((v) => texts(v, "Value"));
    return encodings.length === 0 || encodings.includes("KVP");
  });
  const kvpUrl = href(kvp);
  return {
    service: "WMTS",
    version: root.getAttribute("version") ?? "",
    title: text(at(root, "ServiceIdentification", "Title")),
    getTileUrl: kvpUrl && resolved(kvpUrl, base),
    layers: children(contents, "Layer").map((l) => ({
      id: text(first(l, "Identifier")),
      title: text(first(l, "Title")),
      abstract: optional(l, "Abstract"),
      bounds: boxBounds(first(l, "WGS84BoundingBox")),
      styles: children(l, "Style").map((s) => ({
        id: text(first(s, "Identifier")),
        title: optional(s, "Title"),
        isDefault: s.getAttribute("isDefault") === "true",
        legendUrl: href(first(s, "LegendURL")),
      })),
      formats: texts(l, "Format"),
      infoFormats: texts(l, "InfoFormat"),
      tileMatrixSets: children(l, "TileMatrixSetLink").map((s) => text(first(s, "TileMatrixSet"))),
      resources: children(l, "ResourceURL").map((r) => ({
        format: r.getAttribute("format") ?? "",
        resourceType: r.getAttribute("resourceType") ?? "",
        template: resolved(r.getAttribute("template") ?? "", base),
      })),
      dimensions: children(l, "Dimension").map((d) => ({ id: text(first(d, "Identifier")), default: text(first(d, "Default")), values: texts(d, "Value") })),
    })),
    tileMatrixSets: children(contents, "TileMatrixSet").map((s) => ({
      id: text(first(s, "Identifier")),
      crs: text(first(s, "SupportedCRS")),
      wellKnownScaleSet: optional(s, "WellKnownScaleSet"),
      matrices: children(s, "TileMatrix").map((m) => ({
        id: text(first(m, "Identifier")),
        scale: Number(text(first(m, "ScaleDenominator"))),
        topLeft: numbers(text(first(m, "TopLeftCorner"))).slice(0, 2) as [number, number],
        tileWidth: Number(text(first(m, "TileWidth"))),
        tileHeight: Number(text(first(m, "TileHeight"))),
        matrixWidth: Number(text(first(m, "MatrixWidth"))),
        matrixHeight: Number(text(first(m, "MatrixHeight"))),
      })),
    })),
  };
}

/**
 * The zooms of `set` when it is Web Mercator's quadtree (square tiles on the EPSG:3857 square,
 * 2^z of them across, one zoom after another): `[first, last]`, or null.
 */
export function mercatorZooms(set: WMTSTileMatrixSet): [number, number] | null {
  if (!isWebMercator(set.crs) || set.matrices.length === 0) return null;
  const zooms = set.matrices.map((m) => {
    const z = mercatorZoom(m.scale * OGC_PIXEL_METERS, m.tileWidth);
    const corner = Math.abs(m.topLeft[0] + MERCATOR_HALF) < 1e-2 * 2 ** -z * MERCATOR_HALF && Math.abs(m.topLeft[1] - MERCATOR_HALF) < 1e-2 * 2 ** -z * MERCATOR_HALF;
    return corner && m.tileWidth === m.tileHeight && m.matrixWidth === 2 ** z && m.matrixHeight === 2 ** z ? z : NaN;
  });
  return zooms.every((z, i) => z === zooms[0] + i) ? [zooms[0], zooms[zooms.length - 1]] : null;
}

/**
 * `layer` (an identifier); `style`, `format` and `tileMatrixSet` default to the layer's default
 * style, first format and first Web Mercator set; `dimensions` overrides dimension values (default
 * each one's `Default`).
 */
export interface WMTSSourceOptions {
  layer: string;
  style?: string;
  format?: string;
  tileMatrixSet?: string;
  dimensions?: Record<string, string>;
}

/**
 * A raster source for a WMTS layer in a Web Mercator tile matrix set (RESTful when the layer has a
 * ResourceURL for the format, else KVP), with the layer's bounds and the set's zooms.
 */
export function wmtsSource(capabilities: WMTSCapabilities, options: WMTSSourceOptions): TileSource | ReprojectedSource {
  const layer = capabilities.layers.find((l) => l.id === options.layer);
  if (!layer) throw new Error(`mbmap: services: the WMTS has no layer ${options.layer}`);
  const sets = capabilities.tileMatrixSets.filter((s) => layer.tileMatrixSets.includes(s.id) && (options.tileMatrixSet === undefined || s.id === options.tileMatrixSet));
  const bounds = layer.bounds && { bounds: clampBounds(layer.bounds) };
  const set = sets.map((s) => ({ s, zooms: mercatorZooms(s) })).find((m) => m.zooms);
  if (set) {
    const [minzoom, maxzoom] = set.zooms!;
    const matrix = zoomTemplate(set.s.matrices.map((m) => m.id), minzoom);
    if (matrix === null) throw new Error(`mbmap: services: the tile matrices of ${set.s.id} are not named by zoom`);
    return { type: "raster", tiles: [tileTemplate(capabilities, layer, set.s, options, matrix, "{y}", "{x}")], tileSize: set.s.matrices[0].tileWidth, minzoom, maxzoom, ...bounds };
  }
  // Another CRS: drawn by mbmap/data's worker, which reprojects the set's tiles.
  const other = sets.find((s) => epsgCode(s.crs) !== undefined && s.matrices.length > 0);
  if (!other) throw new Error(`mbmap: services: the WMTS layer ${layer.id} has no tile matrix set in Web Mercator or an EPSG CRS${options.tileMatrixSet ? ` named ${options.tileMatrixSet}` : ""}`);
  const unit = metersPerUnit(other.crs);
  const matrices = other.matrices.map((m) => {
    const [x, y] = northFirst(other.crs) ? [m.topLeft[1], m.topLeft[0]] : m.topLeft;
    return { id: m.id, resolution: (m.scale * OGC_PIXEL_METERS) / unit, x, y, width: m.tileWidth, height: m.tileHeight, cols: m.matrixWidth, rows: m.matrixHeight };
  });
  const finest = Math.min(...matrices.map((m) => m.resolution)) * unit;
  return {
    type: "reprojected",
    crs: epsgCode(other.crs)!,
    grid: { template: tileTemplate(capabilities, layer, other, options, "{TileMatrix}", "{TileRow}", "{TileCol}"), matrices },
    minzoom: 0,
    maxzoom: zoomForResolution(finest, REPROJECTED_TILE_SIZE),
    ...bounds,
  };
}

/** The URL of `layer`'s tiles in `set` with `matrix`, `row` and `col` (templates with braces) for the matrix, row and column. */
function tileTemplate(capabilities: WMTSCapabilities, layer: WMTSLayer, set: WMTSTileMatrixSet, options: WMTSSourceOptions, matrix: string, row: string, col: string): string {
  const style = options.style ?? (layer.styles.find((s) => s.isDefault) ?? layer.styles[0])?.id ?? "default";
  const format = options.format ?? layer.formats[0] ?? layer.resources.find((r) => r.resourceType === "tile")?.format ?? "image/png";
  const values: Record<string, string> = Object.create(null);
  for (const d of layer.dimensions) values[d.id] = options.dimensions?.[d.id] ?? d.default;
  const resource = layer.resources.find((r) => r.resourceType === "tile" && r.format === format);
  if (resource) {
    return resource.template.replace(/\{([^}]+)\}/g, (all, name: string) => {
      const key = name.toLowerCase();
      if (key === "tilematrixset") return encodeURIComponent(set.id);
      if (key === "tilematrix") return matrix.split(/(\{\w+\})/).map((p) => (/^\{\w+\}$/.test(p) ? p : encodeURIComponent(p))).join("");
      if (key === "tilerow") return row;
      if (key === "tilecol") return col;
      if (key === "style") return encodeURIComponent(style);
      const dimension = Object.keys(values).find((d) => d.toLowerCase() === key);
      return dimension === undefined ? all : encodeURIComponent(values[dimension]);
    });
  }
  if (!capabilities.getTileUrl) throw new Error(`mbmap: services: the WMTS layer ${layer.id} has no URL for ${format}`);
  return withQuery(capabilities.getTileUrl, {
    SERVICE: "WMTS",
    REQUEST: "GetTile",
    VERSION: capabilities.version || "1.0.0",
    LAYER: layer.id,
    STYLE: style,
    FORMAT: format,
    TILEMATRIXSET: set.id,
    TILEMATRIX: matrix,
    TILEROW: row,
    TILECOL: col,
    ...values,
  });
}
