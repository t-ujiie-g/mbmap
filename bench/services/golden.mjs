// mbmap/services vs OpenLayers 10.11.0 and @camptocamp/ogc-client 2.0.2 on live public services
// (AGENTS.md §1 `services:golden`), and a tile fetched from each source made. Writes
// bench/results/services-golden.json; behind a proxy Node needs NODE_USE_ENV_PROXY=1.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { DOMParser, Node } from "@xmldom/xmldom";
import WMSCapabilities from "ol/format/WMSCapabilities.js";
import WMTSCapabilities from "ol/format/WMTSCapabilities.js";
import TileWMS from "ol/source/TileWMS.js";
import WMTS, { optionsFromCapabilities } from "ol/source/WMTS.js";
import TileArcGISRest from "ol/source/TileArcGISRest.js";
import { getFeatureInfoUrl, getImageSrc } from "ol/source/wms.js";
import WFSFormat from "ol/format/WFS.js";
import GML2 from "ol/format/GML2.js";
import GML3 from "ol/format/GML3.js";
import GML32 from "ol/format/GML32.js";
import { getRequestUrl as arcgisRequestUrl } from "ol/source/arcgisRest.js";
import { fromLonLat } from "ol/proj.js";
import { get as getProjection } from "ol/proj.js";
import { OgcApiEndpoint } from "@camptocamp/ogc-client";
import { parseXmlString } from "../node_modules/@camptocamp/ogc-client/dist/shared/xml-utils.js";
import * as wfsCaps from "../node_modules/@camptocamp/ogc-client/dist/wfs/capabilities.js";
import { generateGetFeatureUrl } from "../node_modules/@camptocamp/ogc-client/dist/wfs/url.js";
import { simplifyEpsgUrn } from "../node_modules/@camptocamp/ogc-client/dist/shared/crs-utils.js";
import * as services from "../../npm/src/services.ts";
import { readGml } from "../../npm/src/services/gml.ts";
import { ROOT } from "../lib/root.mjs";

globalThis.DOMParser = DOMParser;
globalThis.Node = Node;
// OpenLayers walks elements with these, which xmldom lacks.
const elementFrom = (n) => {
  while (n && n.nodeType !== 1) n = n.nextSibling;
  return n ?? null;
};
Object.defineProperty(Node.prototype, "firstElementChild", { get() { return elementFrom(this.firstChild); } });
Object.defineProperty(Node.prototype, "nextElementSibling", { get() { return elementFrom(this.nextSibling); } });
globalThis.document = { baseURI: "https://example.com/" };

const WMS = [
  "https://demo.mapserver.org/cgi-bin/wms?SERVICE=WMS&REQUEST=GetCapabilities&VERSION=1.3.0",
  "https://demo.mapserver.org/cgi-bin/wms?SERVICE=WMS&REQUEST=GetCapabilities&VERSION=1.1.1",
  "https://sampleserver6.arcgisonline.com/arcgis/services/SampleWorldCities/MapServer/WMSServer?SERVICE=WMS&REQUEST=GetCapabilities&VERSION=1.3.0",
  "https://gibs.earthdata.nasa.gov/wms/epsg3857/best/wms.cgi?SERVICE=WMS&REQUEST=GetCapabilities&VERSION=1.3.0",
];
const WMTS_DOCS = [
  "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/1.0.0/WMTSCapabilities.xml",
  "https://services.arcgisonline.com/arcgis/rest/services/World_Topo_Map/MapServer/WMTS/1.0.0/WMTSCapabilities.xml",
  "https://demo.mapserver.org/mapcache/wmts?SERVICE=WMTS&REQUEST=GetCapabilities",
];
const WFS = [
  "https://demo.mapserver.org/cgi-bin/wfs?SERVICE=WFS&REQUEST=GetCapabilities&VERSION=2.0.0",
  "https://demo.mapserver.org/cgi-bin/wfs?SERVICE=WFS&REQUEST=GetCapabilities&VERSION=1.1.0",
  "https://demo.mapserver.org/cgi-bin/wfs?SERVICE=WFS&REQUEST=GetCapabilities&VERSION=1.0.0",
  "https://sampleserver6.arcgisonline.com/arcgis/services/SampleWorldCities/MapServer/WFSServer?SERVICE=WFS&REQUEST=GetCapabilities&VERSION=2.0.0",
];
const OGC_API = "https://demo.pygeoapi.io/master";
const SAMPLE_CITIES = "https://sampleserver6.arcgisonline.com/arcgis/rest/services/SampleWorldCities/MapServer";
const ARCGIS = [
  "https://services.arcgisonline.com/arcgis/rest/services/World_Topo_Map/MapServer",
  "https://sampleserver6.arcgisonline.com/arcgis/rest/services/SampleWorldCities/MapServer",
  "https://sampleserver6.arcgisonline.com/arcgis/rest/services/Toronto/ImageServer",
];
// One image of an 800 by 600 view at zoom 10 over Tokyo (MapLibre's 512-pixel zooms), and a click at its center.
const TOKYO = [139.80908203125, 35.68310546875];
const RESOLUTION = (2 * Math.PI * 6378137) / (512 * 2 ** 10);
const [CX, CY] = fromLonLat(TOKYO);
const VIEW = [CX - 400 * RESOLUTION, CY - 300 * RESOLUTION, CX + 400 * RESOLUTION, CY + 300 * RESOLUTION];
// Tiles whose URLs both make: around Tokyo and the world.
const TILES = [[0, 0, 0], [3, 7, 3], [5, 28, 12], [10, 909, 403]];

const results = [];
let failed = 0;
const report = (r) => {
  if (!r.ok) failed++;
  results.push(r);
  console.log(JSON.stringify(r).slice(0, 400));
};
const get = async (url) => {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  return res.text();
};
// mbmap resolves a document's URLs against the document, which drops default ports (`:443`).
const href = (u, base) => (u === undefined ? u : new URL(u, base).href);
const trim = (s) => (typeof s === "string" ? s.trim() || undefined : s);
const close = (a, b) => (a === undefined && b === undefined) || (Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((v, i) => Math.abs(v - b[i]) <= 1e-9 * Math.max(1, Math.abs(v))));
// The first difference between `ours` and `theirs`, as a path and the two values.
function diff(ours, theirs, at = "") {
  if (typeof ours === "number" && typeof theirs === "number") return Math.abs(ours - theirs) <= 1e-9 * Math.max(1, Math.abs(ours)) ? null : { at, ours, theirs };
  if (Array.isArray(ours) || Array.isArray(theirs)) {
    if (!Array.isArray(ours) || !Array.isArray(theirs) || ours.length !== theirs.length) return { at, ours, theirs };
    for (let i = 0; i < ours.length; i++) {
      const d = diff(ours[i], theirs[i], `${at}[${i}]`);
      if (d) return d;
    }
    return null;
  }
  if (ours && theirs && typeof ours === "object" && typeof theirs === "object") {
    for (const k of new Set([...Object.keys(ours), ...Object.keys(theirs)])) {
      const d = diff(ours[k], theirs[k], `${at}.${k}`);
      if (d) return d;
    }
    return null;
  }
  return ours === theirs ? null : { at, ours, theirs };
}

// The engine fills `{bbox-epsg-3857}` and the rest as MapLibre does (raster:golden checks that).
function expand(template, [z, x, y]) {
  const r = Math.PI * 6378137, e = (2 * r) / 2 ** z, row = 2 ** z - y - 1;
  const bbox = `${-r + x * e},${r - 2 * r + row * e},${-r + (x + 1) * e},${r - 2 * r + (row + 1) * e}`;
  return template.replaceAll("{z}", z).replaceAll("{x}", x).replaceAll("{y}", y).replaceAll("{bbox-epsg-3857}", bbox);
}
// A URL's path and parameters, names in upper case and BBOX as numbers.
function request(url) {
  const u = new URL(url);
  const params = {};
  for (const [k, v] of u.searchParams) {
    const name = k.toUpperCase();
    params[name] = name === "BBOX" ? v.split(",").map((x) => (Number.isFinite(Number(x)) ? Number(x) : x)) : name === "TRANSPARENT" ? v.toUpperCase() : v;
  }
  return { path: u.origin + decodeURIComponent(u.pathname), params };
}
const sameRequest = (a, b) => diff(request(a), request(b));
// The tile at zoom `z` under the middle of `bounds`.
function tileAt(bounds, z) {
  const [lng, lat] = bounds ? [(bounds[0] + bounds[2]) / 2, (bounds[1] + bounds[3]) / 2] : [0, 0];
  const r = (lat * Math.PI) / 180;
  return [z, Math.floor(((lng + 180) / 360) * 2 ** z), Math.floor(((1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2) * 2 ** z)];
}
const fetchesImage = async (url) => {
  const res = await fetch(url);
  const type = res.headers.get("content-type") ?? "";
  await res.arrayBuffer();
  return res.ok && /^image\//.test(type) ? true : `${res.status} ${type}`;
};

// OpenLayers reads sublayers before adding what their parent inherits, so a grandchild misses its
// grandparent's CRSs, styles and values: its tree is completed here by WMS 1.3.0 §7.2.4.8 (a layer's
// own items are those beyond its parent's own; the rest comes from the completed parent).
function inherit(layer, parent, parentOwn) {
  const own = {};
  for (const key of ["crs", "styles"]) {
    own[key] = parentOwn ? layer[key].slice(0, layer[key].length - parentOwn[key].length) : layer[key];
    if (parent) layer[key] = [...own[key], ...parent[key]];
  }
  if (parent) {
    for (const key of ["bounds", "boundingBoxes", "minScale", "maxScale", "attribution"]) {
      const missing = key === "boundingBoxes" ? layer[key].length === 0 : layer[key] === undefined;
      if (missing) layer[key] = parent[key];
    }
  }
  layer.layers = layer.layers.map((child) => inherit(child, layer, own));
  return layer;
}

// WMS: every layer as OpenLayers reads it, then GetMap URLs.
for (const url of WMS) {
  try {
    const xml = await get(url);
    const ours = services.readWMSCapabilities(xml, url);
    const ol = new WMSCapabilities().read(xml);
    const v13 = ol.version !== "1.1.1";
    const olLayer = (l) => ({
      name: trim(l.Name),
      title: trim(l.Title) ?? "",
      abstract: trim(l.Abstract),
      crs: (v13 ? l.CRS : l.SRS) ?? [],
      bounds: v13 ? l.EX_GeographicBoundingBox : l.LatLonBoundingBox?.extent,
      boundingBoxes: (l.BoundingBox ?? []).map((b) => ({ crs: b.crs ?? b.srs, bbox: b.extent })),
      styles: (l.Style ?? []).map((s) => ({ name: trim(s.Name) ?? "", title: trim(s.Title) ?? "", legendUrl: s.LegendURL?.[0]?.OnlineResource })),
      queryable: l.queryable,
      opaque: l.opaque,
      minScale: v13 ? l.MinScaleDenominator : l.ScaleHint?.[0]?.min !== undefined ? Math.sqrt(0.5 * l.ScaleHint[0].min ** 2) / 0.00028 : undefined,
      maxScale: v13 ? l.MaxScaleDenominator : l.ScaleHint?.[0]?.max !== undefined ? Math.sqrt(0.5 * l.ScaleHint[0].max ** 2) / 0.00028 : undefined,
      attribution: l.Attribution ? { title: trim(l.Attribution.Title), url: l.Attribution.OnlineResource } : undefined,
      layers: (l.Layer ?? []).map(olLayer),
    });
    const theirs = {
      service: "WMS",
      version: ol.version,
      title: trim(ol.Service.Title) ?? "",
      abstract: trim(ol.Service.Abstract),
      getMapUrl: href(ol.Capability.Request.GetMap.DCPType[0].HTTP.Get.OnlineResource, url),
      getFeatureInfoUrl: href(ol.Capability.Request.GetFeatureInfo?.DCPType[0].HTTP.Get.OnlineResource, url),
      mapFormats: ol.Capability.Request.GetMap.Format,
      infoFormats: ol.Capability.Request.GetFeatureInfo?.Format ?? [],
      layers: [inherit(olLayer(ol.Capability.Layer), null, null)],
    };
    // OpenLayers reads no attribute of the top layer when it has sublayers, so its queryable and opaque
    // are left out, and the sublayers' too where it sets them (WMS 1.3.0 §7.2.4.8 has them inherited).
    const top = new DOMParser().parseFromString(xml, "application/xml").getElementsByTagNameNS("*", "Layer")[0];
    const leaveOut = ["queryable", "opaque"].filter((a) => top?.getAttribute(a));
    const strip = (l, top) => {
      for (const a of top ? ["queryable", "opaque"] : leaveOut) delete l[a];
      l.layers.forEach((child) => strip(child, false));
    };
    const mine = structuredClone(ours);
    mine.layers.forEach((l) => strip(l, true));
    theirs.layers.forEach((l) => strip(l, true));
    const d = diff(mine, theirs);
    const all = services.allLayers(ours.layers);
    report({ check: "wms capabilities", url, version: ours.version, layers: all.length, leftOut: leaveOut, ok: d === null, ...(d && { diff: d }) });

    const named = all.filter((l) => l.name && l.layers.length === 0 && l.crs.some(services.isWebMercator)).slice(0, 3);
    for (const layer of named) {
      const source = services.wmsSource(ours, { layers: layer.name });
      const ol3857 = new TileWMS({
        url: ours.getMapUrl,
        params: { LAYERS: layer.name, FORMAT: "image/png", TRANSPARENT: true, VERSION: ours.version, STYLES: "" },
        projection: "EPSG:3857",
      });
      const grid = ol3857.getTileGridForProjection(getProjection("EPSG:3857"));
      const mismatch = TILES.map((t) => {
        const olUrl = ol3857.getTileUrlFunction()([t[0], t[1], t[2]], 1, getProjection("EPSG:3857"));
        return grid && sameRequest(expand(source.tiles[0], t), olUrl);
      }).find((x) => x);
      const fetched = await fetchesImage(expand(source.tiles[0], TILES[2]));
      report({ check: "wms source", url, layer: layer.name, ok: !mismatch && fetched === true, ...(mismatch && { diff: mismatch }), fetched, bounds: source.bounds });
    }
    // One image and GetFeatureInfo as OpenLayers' ImageWMS asks them (ratio 1).
    const queryable = all.filter((l) => l.name && l.queryable && l.crs.some(services.isWebMercator));
    for (const layer of [queryable[0] ?? named[0]].filter(Boolean)) {
      const params = { SERVICE: "WMS", VERSION: ours.version, LAYERS: layer.name, STYLES: "", FORMAT: "image/png", TRANSPARENT: "TRUE" };
      const image = services.wmsImage(ours, { layers: layer.name })(VIEW, 800, 600, 1);
      const di = sameRequest(image, getImageSrc(VIEW, RESOLUTION, 1, getProjection("EPSG:3857"), ours.getMapUrl, params));
      const fetched = await fetchesImage(image);
      let info = null;
      if (layer.queryable && ours.getFeatureInfoUrl && ours.infoFormats.length) {
        const format = ours.infoFormats.find((f) => /json/i.test(f)) ?? ours.infoFormats[0];
        const mine = services.wmsFeatureInfoUrl(ours, { layers: layer.name, infoFormat: format }, TOKYO, 10);
        const theirs = getFeatureInfoUrl({ url: ours.getFeatureInfoUrl, params: { ...params, INFO_FORMAT: format }, projection: "EPSG:3857" }, [CX, CY], RESOLUTION);
        info = { format, diff: sameRequest(mine, theirs), status: (await fetch(mine)).status };
      }
      report({ check: "wms image", url, layer: layer.name, ok: di === null && fetched === true && (!info || (info.diff === null && info.status === 200)), ...(di && { diff: di }), fetched, info });
    }
  } catch (e) {
    report({ check: "wms", url, ok: false, error: String(e) });
  }
}

// WMTS: layers and tile matrix sets as OpenLayers reads them, then tile URLs from its optionsFromCapabilities.
for (const url of WMTS_DOCS) {
  try {
    const xml = await get(url);
    const ours = services.readWMTSCapabilities(xml, url);
    const ol = new WMTSCapabilities().read(xml);
    const theirs = {
      layers: ol.Contents.Layer.map((l) => ({
        id: l.Identifier,
        title: trim(l.Title) ?? "",
        bounds: l.WGS84BoundingBox,
        formats: l.Format ?? [],
        styles: (l.Style ?? []).map((s) => ({ id: s.Identifier, isDefault: !!s.isDefault })),
        tileMatrixSets: (l.TileMatrixSetLink ?? []).map((s) => s.TileMatrixSet),
        resources: (l.ResourceURL ?? []).map((r) => ({ format: r.format, resourceType: r.resourceType, template: r.template })),
      })),
      tileMatrixSets: ol.Contents.TileMatrixSet.map((s) => ({
        id: s.Identifier,
        crs: s.SupportedCRS,
        matrices: s.TileMatrix.map((m) => ({ id: m.Identifier, scale: m.ScaleDenominator, topLeft: m.TopLeftCorner, tileWidth: m.TileWidth, tileHeight: m.TileHeight, matrixWidth: m.MatrixWidth, matrixHeight: m.MatrixHeight })),
      })),
    };
    const mine = {
      layers: ours.layers.map((l) => ({ id: l.id, title: l.title, bounds: l.bounds, formats: l.formats, styles: l.styles.map((s) => ({ id: s.id, isDefault: s.isDefault })), tileMatrixSets: l.tileMatrixSets, resources: l.resources })),
      tileMatrixSets: ours.tileMatrixSets.map((s) => ({ id: s.id, crs: s.crs, matrices: s.matrices })),
    };
    const d = diff(mine, theirs);
    report({ check: "wmts capabilities", url, layers: ours.layers.length, sets: ours.tileMatrixSets.length, ok: d === null, ...(d && { diff: d }) });

    const layers = ours.layers.filter((l) => l.tileMatrixSets.some((id) => services.mercatorZooms(ours.tileMatrixSets.find((s) => s.id === id)))).slice(0, 3);
    for (const layer of layers) {
      const source = services.wmtsSource(ours, { layer: layer.id });
      const set = ours.tileMatrixSets.find((s) => layer.tileMatrixSets.includes(s.id) && services.mercatorZooms(s));
      const rest = layer.resources.some((r) => r.resourceType === "tile" && r.format === layer.formats[0]);
      const options = optionsFromCapabilities(ol, { layer: layer.id, matrixSet: set.id, format: layer.formats[0], requestEncoding: rest ? "REST" : "KVP" });
      // OpenLayers spreads tiles over every ResourceURL of the format; mbmap takes the first.
      const olSource = new WMTS({ ...options, urls: options.urls.slice(0, 1) });
      const tiles = TILES.filter(([z]) => z >= source.minzoom && z <= source.maxzoom);
      const mismatch = tiles.map((t) => {
        const olUrl = olSource.getTileUrlFunction()([t[0] - source.minzoom, t[1], t[2]], 1, getProjection("EPSG:3857"));
        return expand(source.tiles[0], t) === olUrl ? null : sameRequest(expand(source.tiles[0], t), olUrl) && { ours: expand(source.tiles[0], t), theirs: olUrl };
      }).find((x) => x);
      const fetched = await fetchesImage(expand(source.tiles[0], tiles.at(-1)));
      report({ check: "wmts source", url, layer: layer.id, set: set.id, encoding: rest ? "REST" : "KVP", zooms: [source.minzoom, source.maxzoom], ok: !mismatch && fetched === true, ...(mismatch && { diff: mismatch }), fetched });
    }
  } catch (e) {
    report({ check: "wmts", url, ok: false, error: String(e) });
  }
}

// WFS: feature types as ogc-client reads them (it shortens EPSG URNs, so both are compared shortened).
for (const url of WFS) {
  try {
    const xml = await get(url);
    const ours = services.readWFSCapabilities(xml, url);
    const doc = parseXmlString(xml);
    const urls = wfsCaps.readOperationUrlsFromCapabilities(doc);
    const theirs = {
      version: wfsCaps.readVersionFromCapabilities(doc),
      getFeatureUrl: href(urls.GetFeature?.Get, url),
      outputFormats: wfsCaps.readOutputFormatsFromCapabilities(doc),
      featureTypes: wfsCaps.readFeatureTypesFromCapabilities(doc).map((f) => ({
        name: f.name,
        title: trim(f.title),
        abstract: trim(f.abstract),
        defaultCrs: trim(f.defaultCrs),
        otherCrs: f.otherCrs,
        bounds: f.latLonBoundingBox,
      })),
    };
    const mine = {
      version: ours.version,
      getFeatureUrl: ours.getFeatureUrl,
      outputFormats: ours.outputFormats,
      featureTypes: ours.featureTypes.map((f) => ({
        name: f.name,
        title: f.title,
        abstract: f.abstract,
        defaultCrs: f.defaultCrs && simplifyEpsgUrn(f.defaultCrs),
        otherCrs: f.otherCrs.map(simplifyEpsgUrn),
        bounds: f.bounds,
      })),
    };
    const d = diff(mine, theirs);
    report({ check: "wfs capabilities", url, version: ours.version, types: ours.featureTypes.length, ok: d === null, ...(d && { diff: d }) });
  } catch (e) {
    report({ check: "wfs", url, ok: false, error: String(e) });
  }
}

// OGC API: collections and WebMercatorQuad tilesets as ogc-client finds them.
try {
  const ours = await services.ogcCollections(OGC_API);
  const endpoint = new OgcApiEndpoint(OGC_API);
  const ids = (await endpoint.allCollections).map((c) => c.name);
  const d = diff(ours.map((c) => c.id), ids);
  report({ check: "ogc api collections", url: OGC_API, collections: ours.length, ok: d === null, ...(d && { diff: d }) });
  for (const c of ours) {
    const info = await endpoint.getCollectionInfo(c.id);
    const theirs = { title: info.title, description: info.description, bounds: info.extent?.spatial?.bbox?.[0]?.slice(0, 4) ?? info.bbox?.slice(0, 4), itemType: info.itemType };
    const di = diff({ title: c.title, description: c.description, bounds: c.bounds, itemType: c.itemType }, theirs);
    const tiles = {};
    for (const kind of ["vector", "map"]) {
      if (!(kind === "vector" ? c.vectorTilesUrl : c.mapTilesUrl)) continue;
      const theirUrl = await (kind === "vector" ? endpoint.getVectorTilesetUrl(c.id) : endpoint.getMapTilesetUrl(c.id)).catch(() => undefined);
      const listUrl = kind === "vector" ? c.vectorTilesUrl : c.mapTilesUrl;
      const ourUrl = services.ogcTilesetUrl(JSON.parse(await get(listUrl)), listUrl);
      const source = await services.ogcTiles(c, kind);
      const res = await fetch(expand(source.tiles[0], tileAt(c.bounds, source.minzoom ?? 0)));
      await res.arrayBuffer();
      tiles[kind] = { same: ourUrl === theirUrl, ...(ourUrl !== theirUrl && { ours: ourUrl, theirs: theirUrl }), type: source.type, zooms: [source.minzoom, source.maxzoom], status: res.status };
    }
    const ok = di === null && Object.values(tiles).every((t) => t.same && t.status === 200);
    report({ check: "ogc api collection", id: c.id, ok, ...(di && { diff: di }), tiles });
  }
} catch (e) {
  report({ check: "ogc api", url: OGC_API, ok: false, error: String(e) });
}

// ArcGIS: cached services by their tiles, others by `export` as OpenLayers' TileArcGISRest asks.
for (const url of ARCGIS) {
  try {
    const service = await services.arcgisService(url);
    const source = services.arcgisSource(service, url);
    const cached = source.tiles[0].includes("/tile/");
    let mismatch = null;
    if (!cached) {
      const image = /ImageServer$/.test(url);
      const ol = new TileArcGISRest({ url, params: image ? { FORMAT: "png" } : { dpi: 96 }, projection: "EPSG:3857" });
      mismatch = TILES.map((t) => {
        const theirs = request(ol.getTileUrlFunction()([t[0], t[1], t[2]], 1, getProjection("EPSG:3857")));
        const ours = request(expand(source.tiles[0], t));
        // OpenLayers asks for DPI 96 even of an ImageServer, which takes no dpi.
        if (image) delete theirs.params.DPI;
        return diff(ours, theirs);
      }).find((x) => x);
    }
    // One image as OpenLayers' ImageArcGISRest asks it (ratio 1, dpi 96).
    let image = null;
    if (/(MapServer|ImageServer)$/.test(url)) {
      const ours = services.arcgisImage(url)(VIEW, 800, 600, 1);
      const theirs = request(arcgisRequestUrl(url, VIEW, RESOLUTION, 1, getProjection("EPSG:3857"), /ImageServer$/.test(url) ? { FORMAT: "png", TRANSPARENT: true, F: "image" } : { dpi: 96, FORMAT: "png32", TRANSPARENT: true, F: "image" }));
      if (/ImageServer$/.test(url)) delete theirs.params.DPI;
      image = { diff: diff(request(ours), theirs), fetched: await fetchesImage(ours) };
      mismatch ??= image.diff;
    }
    const tile = cached ? tileAt(source.bounds, Math.max(source.minzoom ?? 0, 12)) : TILES[2];
    const fetched = await fetchesImage(expand(source.tiles[0], tile));
    report({ check: "arcgis source", url, cached, zooms: cached ? [source.minzoom, source.maxzoom] : undefined, bounds: source.bounds, ok: !mismatch && fetched === true && (!image || image.fetched === true), ...(mismatch && { diff: mismatch }), fetched, image: image?.fetched });
  } catch (e) {
    report({ check: "arcgis", url, ok: false, error: String(e) });
  }
}

// Features: every page gathered, against what one request (or the server's id list) gives.
const ids = (fc) => fc.features.map((f) => f.id ?? JSON.stringify(f.properties)).map(String).sort();
const JAPAN = [129, 30, 146, 46];
try {
  const items = `${OGC_API}/collections/lakes/items`;
  // ogc-client's getCollectionItems takes one page and the server caps a page at 10: the reference
  // is the count the server says matches, every id once.
  const { numberMatched } = JSON.parse(await get(`${items}?f=json&limit=1`));
  const ours = await services.ogcFeatures(items, { limit: 5 });
  const d = diff([ours.features.length, new Set(ids(ours)).size], [numberMatched, numberMatched]);
  const boxed = await services.ogcFeatures(items, { limit: 3, bbox: [-100, 40, -70, 60] });
  const single = JSON.parse(await get(`${items}?f=json&limit=1000&bbox=-100,40,-70,60`));
  const db = diff(ids(boxed), ids(single));
  report({ check: "ogc api features", url: items, features: ours.features.length, boxed: boxed.features.length, ok: d === null && db === null && ours.features.length > 5, ...((d ?? db) && { diff: d ?? db }) });
} catch (e) {
  report({ check: "ogc api features", ok: false, error: String(e) });
}
try {
  const url = WFS[0];
  const caps = services.readWFSCapabilities(await get(url), url);
  const format = "application/json; subtype=geojson";
  const paged = await services.wfsFeatures(caps, { typeName: "ms:cities", count: 3000 });
  const whole = JSON.parse(await get(services.wfsFeatureUrl(caps.getFeatureUrl, caps.version, { typeName: "ms:cities", outputFormat: format })));
  const d = diff(ids(paged), ids(whole));
  const ours = services.wfsFeatureUrl(caps.getFeatureUrl, "2.0.0", { typeName: "ms:cities", outputFormat: format, count: 40, startIndex: 80, bbox: [139, 35, 140, 36] });
  const theirs = generateGetFeatureUrl(caps.getFeatureUrl, "2.0.0", "ms:cities", format, 40, undefined, false, undefined, [35, 139, 36, 140], "urn:ogc:def:crs:EPSG::4326", 80);
  const du = sameRequest(ours, theirs);
  const boxed = await services.wfsFeatures(caps, { typeName: "ms:cities", bbox: [139, 35, 140, 36] });
  const japan = boxed.features.every((f) => f.geometry.coordinates[0] >= 139 && f.geometry.coordinates[0] <= 140 && f.geometry.coordinates[1] >= 35 && f.geometry.coordinates[1] <= 36);
  report({ check: "wfs features", url, features: paged.features.length, boxed: boxed.features.length, ok: d === null && du === null && paged.features.length > 3000 && boxed.features.length > 0 && japan, ...((d ?? du) && { diff: d ?? du }) });
} catch (e) {
  report({ check: "wfs features", ok: false, error: String(e) });
}
try {
  const layer = "https://sampleserver6.arcgisonline.com/arcgis/rest/services/SampleWorldCities/MapServer/0";
  const all = await services.arcgisFeatures(layer, { count: 300, format: "geojson" });
  const known = JSON.parse(await get(`${layer}/query?where=1%3D1&returnIdsOnly=true&f=json`)).objectIds.map(String).sort();
  const d = diff(ids(all), known);
  const boxed = await services.arcgisFeatures(layer, { bbox: JAPAN, format: "geojson" });
  const inBox = JSON.parse(await get(`${layer}/query?where=1%3D1&geometry=${JAPAN.join(",")}&geometryType=esriGeometryEnvelope&inSR=4326&spatialRel=esriSpatialRelIntersects&returnIdsOnly=true&f=json`)).objectIds.map(String).sort();
  const db = diff(ids(boxed), inBox);
  report({ check: "arcgis features", url: layer, features: all.features.length, boxed: boxed.features.length, ok: d === null && db === null && all.features.length > 300, ...((d ?? db) && { diff: d ?? db }) });
} catch (e) {
  report({ check: "arcgis features", ok: false, error: String(e) });
}

// GML: hand-written documents against what they hold, then the live WFS's GML formats: geometry against its GeoJSON
// answer to the same query, properties against OpenLayers' WFS reader (attributes it adds as `_content_` objects read
// as their content; boundedBy left out).
const GML_NS = 'xmlns:gml="http://www.opengis.net/gml" xmlns:wfs="http://www.opengis.net/wfs" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:a="urn:a"';
const GML_CASES = [
  {
    name: "GML 2 coordinates, polygons with holes, nil and nested values",
    xml: `<wfs:FeatureCollection ${GML_NS}><gml:featureMember><a:t fid="t.1"><a:geom><gml:MultiPolygon srsName="http://www.opengis.net/gml/srs/epsg.xml#4326"><gml:polygonMember><gml:Polygon><gml:outerBoundaryIs><gml:LinearRing><gml:coordinates cs=";" ts="|">0;0|4;0|4;4|0;0</gml:coordinates></gml:LinearRing></gml:outerBoundaryIs><gml:innerBoundaryIs><gml:LinearRing><gml:coordinates>1,1 2,1 2,2 1,1</gml:coordinates></gml:LinearRing></gml:innerBoundaryIs></gml:Polygon></gml:polygonMember></gml:MultiPolygon></a:geom><a:name>x</a:name><a:empty xsi:nil="true"/><a:tag>p</a:tag><a:tag>q</a:tag><a:addr><a:city>c</a:city></a:addr></a:t></gml:featureMember></wfs:FeatureCollection>`,
    want: [{ type: "Feature", id: "t.1", geometry: { type: "MultiPolygon", coordinates: [[[[0, 0], [4, 0], [4, 4], [0, 0]], [[1, 1], [2, 1], [2, 2], [1, 1]]]] }, properties: { name: "x", empty: null, tag: ["p", "q"], addr: { city: "c" } } }],
  },
  {
    name: "GML 3 posList in a URN of EPSG:4326 (latitude first), 3D, Surface patches and Curve segments",
    xml: `<wfs:FeatureCollection ${GML_NS}><gml:featureMembers><a:t gml:id="t.2"><a:geom><gml:Surface srsName="urn:ogc:def:crs:EPSG::4326"><gml:patches><gml:PolygonPatch><gml:exterior><gml:LinearRing><gml:posList srsDimension="3">35 139 9 35 140 9 36 140 9 35 139 9</gml:posList></gml:LinearRing></gml:exterior></gml:PolygonPatch></gml:patches></gml:Surface></a:geom></a:t><a:t gml:id="t.3"><a:geom><gml:Curve srsName="urn:ogc:def:crs:EPSG::4326"><gml:segments><gml:LineStringSegment><gml:posList>35 139 36 140</gml:posList></gml:LineStringSegment><gml:LineStringSegment><gml:pos>36 140</gml:pos><gml:pos>37 141</gml:pos></gml:LineStringSegment></gml:segments></gml:Curve></a:geom></a:t></gml:featureMembers></wfs:FeatureCollection>`,
    want: [
      { type: "Feature", id: "t.2", geometry: { type: "Polygon", coordinates: [[[139, 35], [140, 35], [140, 36], [139, 35]]] }, properties: {} },
      { type: "Feature", id: "t.3", geometry: { type: "LineString", coordinates: [[139, 35], [140, 36], [140, 36], [141, 37]] }, properties: {} },
    ],
  },
  {
    name: "a bare EPSG:4326 as asked, CRS84, multi points and curves",
    latitudeFirst: true,
    xml: `<wfs:FeatureCollection ${GML_NS}><gml:featureMember><a:t><a:p><gml:Point srsName="EPSG:4326"><gml:pos>35 139</gml:pos></gml:Point></a:p></a:t></gml:featureMember><gml:featureMember><a:t><a:p><gml:MultiPoint srsName="urn:ogc:def:crs:OGC:1.3:CRS84"><gml:pointMember><gml:Point><gml:pos>139 35</gml:pos></gml:Point></gml:pointMember><gml:pointMembers><gml:Point><gml:pos>140 36</gml:pos></gml:Point></gml:pointMembers></gml:MultiPoint></a:p></a:t></gml:featureMember><gml:featureMember><a:t><a:p><gml:MultiCurve srsName="CRS:84"><gml:curveMember><gml:LineString><gml:posList>1 2 3 4</gml:posList></gml:LineString></gml:curveMember></gml:MultiCurve></a:p></a:t></gml:featureMember></wfs:FeatureCollection>`,
    want: [
      { type: "Feature", geometry: { type: "Point", coordinates: [139, 35] }, properties: {} },
      { type: "Feature", geometry: { type: "MultiPoint", coordinates: [[139, 35], [140, 36]] }, properties: {} },
      { type: "Feature", geometry: { type: "MultiLineString", coordinates: [[[1, 2], [3, 4]]] }, properties: {} },
    ],
  },
];
for (const c of GML_CASES) {
  try {
    const got = readGml(c.xml, c.latitudeFirst ?? false).features;
    const d = diff(JSON.parse(JSON.stringify(got)), c.want);
    report({ check: "gml case", name: c.name, ok: d === null, ...(d && { diff: d }) });
  } catch (e) {
    report({ check: "gml case", name: c.name, ok: false, error: String(e) });
  }
}
try {
  readGml(`<wfs:FeatureCollection ${GML_NS}><gml:featureMember><a:t><a:p><gml:Point srsName="EPSG:6677"><gml:pos>1 2</gml:pos></gml:Point></a:p></a:t></gml:featureMember></wfs:FeatureCollection>`);
  report({ check: "gml case", name: "another CRS is refused", ok: false });
} catch (e) {
  report({ check: "gml case", name: "another CRS is refused", ok: /EPSG:6677 is not read/.test(String(e)) });
}
// OpenLayers' properties of a feature: its values but the geometry and boundedBy, `{ _content_ }` objects as their content.
function olProperties(f) {
  const out = {};
  const plain = (v) => (v && typeof v === "object" && !Array.isArray(v) && "_content_" in v ? (v._content_ ?? null) : Array.isArray(v) ? v.map(plain) : v);
  for (const [k, v] of Object.entries(f.getProperties())) if (k !== f.getGeometryName() && k !== "boundedBy" && v !== undefined) out[k] = plain(v);
  return out;
}
for (const url of WFS.slice(0, 3)) {
  try {
    const caps = services.readWFSCapabilities(await get(url), url);
    const type = caps.featureTypes.find((t) => /^(ms:)?cities$/.test(t.name));
    const formats = (type.outputFormats.length ? type.outputFormats : caps.outputFormats).filter((f) => /gml/i.test(f));
    const options = { typeName: type.name, bbox: JAPAN };
    const json = await services.wfsFeatures(caps, { ...options, outputFormat: services.geojsonFormat(type.outputFormats.length ? type.outputFormats : caps.outputFormats) });
    // Each feature's name and position (to 1e-5°, as the formats print them), in one order.
    const points = (fc) => fc.features.map((f) => `${f.properties.NAME} ${f.geometry.coordinates.map((v) => (Math.round(v * 1e5) / 1e5).toFixed(5))}`).sort();
    for (const format of formats) {
      const ours = await services.wfsFeatures(caps, { ...options, outputFormat: format });
      const geometry = diff(points(ours), points(json));
      const v10 = caps.version.startsWith("1.0");
      const gmlUrl = services.wfsFeatureUrl(caps.getFeatureUrl, caps.version, { ...options, outputFormat: format, crs: v10 ? "EPSG:4326" : "urn:ogc:def:crs:EPSG::4326" });
      const gmlFormat = /3\.2/.test(format) ? new GML32() : /3\.1|GML3/i.test(format) ? new GML3() : new GML2();
      const ol = new WFSFormat({ version: caps.version, gmlFormat }).readFeatures(await get(gmlUrl));
      const properties = diff(ours.features.map((f) => f.properties), ol.map(olProperties));
      const ids = diff(ours.features.map((f) => f.id), ol.map((f) => f.getId()));
      const d = geometry ?? properties ?? ids;
      report({ check: "wfs gml", version: caps.version, format, features: ours.features.length, ok: d === null && ours.features.length > 0 && ours.features.length === json.features.length, ...(d && { diff: d }) });
    }
  } catch (e) {
    report({ check: "wfs gml", url, ok: false, error: String(e) });
  }
}

// ArcGIS Server's WFS in GML: the cities around Japan come back inside the box asked.
try {
  const url = WFS[3];
  const caps = services.readWFSCapabilities(await get(url), url);
  const type = caps.featureTypes[0];
  const format = services.gmlFormat(type.outputFormats.length ? type.outputFormats : caps.outputFormats);
  const got = await services.wfsFeatures(caps, { typeName: type.name, bbox: JAPAN, outputFormat: format });
  const inside = got.features.every((f) => f.geometry.type === "Point" && f.geometry.coordinates[0] >= JAPAN[0] && f.geometry.coordinates[0] <= JAPAN[2] && f.geometry.coordinates[1] >= JAPAN[1] && f.geometry.coordinates[1] <= JAPAN[3]);
  report({ check: "wfs gml", url, format, features: got.features.length, ok: got.features.length > 0 && inside });
} catch (e) {
  report({ check: "wfs gml", url: WFS[3], ok: false, error: String(e) });
}

// A WMTS of EPSG:4326 only (GIBS): a reprojected source, its first matrix at the world's top-left corner, its tiles images.
try {
  const url = "https://gibs.earthdata.nasa.gov/wmts/epsg4326/best/1.0.0/WMTSCapabilities.xml";
  const caps = services.readWMTSCapabilities(await get(url), url);
  const layer = caps.layers.find((l) => l.id === "BlueMarble_ShadedRelief") ?? caps.layers[0];
  const source = services.wmtsSource(caps, { layer: layer.id });
  const m = source.grid?.matrices[0];
  const tileUrl = source.grid?.template.replace("{TileMatrix}", encodeURIComponent(m.id)).replace("{TileRow}", 0).replace("{TileCol}", 0);
  const fetched = tileUrl && (await fetchesImage(tileUrl));
  const corner = m && Math.abs(m.x + 180) < 1e-9 && Math.abs(m.y - 90) < 1e-9;
  report({ check: "wmts reprojected", url, layer: layer.id, crs: source.crs, matrices: source.grid?.matrices.length, maxzoom: source.maxzoom, ok: source.type === "reprojected" && source.crs === 4326 && corner && fetched === true, fetched });
} catch (e) {
  report({ check: "wmts reprojected", ok: false, error: String(e) });
}

// A click on Tokyo in SampleWorldCities: identify finds the city.
try {
  const identify = JSON.parse(await get(services.arcgisIdentifyUrl(SAMPLE_CITIES, TOKYO, 10, { layers: "all:0" })));
  const found = (identify.results ?? []).map((r) => [r.layerId, r.attributes?.CITY_NAME, r.geometryType]);
  report({ check: "arcgis identify", found, ok: found.some(([id, name, type]) => id === 0 && name === "Tokyo" && type === "esriGeometryPoint") });
} catch (e) {
  report({ check: "arcgis identify", ok: false, error: String(e) });
}

await writeFile(path.join(ROOT, "bench/results/services-golden.json"), JSON.stringify({ env: { ol: "10.11.0", "ogc-client": "2.0.2", node: process.version }, results }, null, 2) + "\n");
console.log(`${results.length - failed} of ${results.length} ok`);
if (failed) process.exit(1);
