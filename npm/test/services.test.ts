import assert from "node:assert/strict";
import test from "node:test";
import { arcgisBounds, arcgisSource, arcgisVectorStyle, arcgisZooms, type ArcGISService } from "../src/services/arcgis.ts";
import { clampBounds, isWebMercator, MERCATOR_HALF, mercatorToLngLat, mercatorZoom, resolved, validBounds, withQuery, zoomTemplate } from "../src/services/common.ts";
import { isWebMercatorQuad, ogcLink, ogcLinks, ogcTileSource, ogcTilesetUrl, readOGCCollection, readOGCCollections } from "../src/services/ogcapi.ts";
import { allLayers, type WMSCapabilities, type WMSLayer, wmsSource } from "../src/services/wms.ts";
import { mercatorZooms, type WMTSCapabilities, type WMTSTileMatrixSet, wmtsSource } from "../src/services/wmts.ts";

test("withQuery replaces parameters in any case, keeps others and the engine's placeholders", () => {
  assert.equal(
    withQuery("https://a.test/wms?map=x&service=WFS&Request=foo#frag", { SERVICE: "WMS", REQUEST: "GetMap", BBOX: "{bbox-epsg-3857}", LAYERS: "a b,c", NONE: undefined }),
    "https://a.test/wms?map=x&SERVICE=WMS&REQUEST=GetMap&BBOX={bbox-epsg-3857}&LAYERS=a%20b%2Cc",
  );
  assert.equal(withQuery("https://a.test/x", { f: "json" }), "https://a.test/x?f=json");
  assert.equal(withQuery("https://a.test/x?", { TILEMATRIX: "EPSG:3857:{z}" }), "https://a.test/x?TILEMATRIX=EPSG%3A3857%3A{z}");
});

test("isWebMercator knows EPSG:3857 and its aliases in every form", () => {
  for (const crs of ["EPSG:3857", "epsg:3857", "urn:ogc:def:crs:EPSG::3857", "http://www.opengis.net/def/crs/EPSG/0/3857", "EPSG:900913", 102100, "102113"]) {
    assert.equal(isWebMercator(crs), true, String(crs));
  }
  for (const crs of ["EPSG:4326", "CRS:84", "", undefined, "EPSG:38570"]) assert.equal(isWebMercator(crs), false, String(crs));
});

test("mercatorZoom finds the zoom of a resolution, NaN off the pyramid", () => {
  assert.equal(mercatorZoom(156543.03392804097, 256), 0);
  assert.equal(mercatorZoom(156543.03392804097 / 2 ** 14, 256), 14);
  assert.equal(mercatorZoom(156543.03392804097 / 2, 512), 0);
  assert.ok(Number.isNaN(mercatorZoom(100000, 256)));
  assert.ok(Number.isNaN(mercatorZoom(156543.03392804097 * 2, 256)));
});

test("mercatorToLngLat inverts Web Mercator", () => {
  assert.deepEqual(mercatorToLngLat(0, 0), [0, 0]);
  const [lng, lat] = mercatorToLngLat(MERCATOR_HALF, MERCATOR_HALF);
  assert.equal(lng, 180);
  assert.ok(Math.abs(lat - 85.0511287798066) < 1e-9);
});

test("zoomTemplate names zooms by one prefix and suffix, or not at all", () => {
  assert.equal(zoomTemplate(["0", "1", "2"], 0), "{z}");
  assert.equal(zoomTemplate(["EPSG:3857:3", "EPSG:3857:4"], 3), "EPSG:3857:{z}");
  assert.equal(zoomTemplate(["L3x", "L4x"], 3), "L{z}x");
  // Zero-padded ids fit a prefix only until the zoom gains a digit.
  assert.equal(zoomTemplate(["00", "01"], 0), "0{z}");
  assert.equal(zoomTemplate(Array.from({ length: 11 }, (_, z) => String(z).padStart(2, "0")), 0), null);
  assert.equal(zoomTemplate(["a", "b"], 0), null);
  assert.equal(zoomTemplate([], 0), null);
});

test("validBounds and clampBounds", () => {
  assert.deepEqual(validBounds([-180.0001, -91, 180.0001, 91]), [-180.0001, -91, 180.0001, 91]);
  assert.equal(validBounds([1, 0, 0, 1]), undefined);
  assert.equal(validBounds([0, 0, NaN, 1]), undefined);
  assert.equal(validBounds([0, 0, 1]), undefined);
  assert.equal(validBounds(undefined), undefined);
  assert.deepEqual(clampBounds([-181, -91, 181, 91]), [-180, -90, 180, 90]);
});

test("resolved resolves against a document's URL and keeps template braces", () => {
  assert.equal(resolved("tiles/{TileMatrix}/{TileCol}.png", "https://a.test/wmts/caps.xml"), "https://a.test/wmts/tiles/{TileMatrix}/{TileCol}.png");
  assert.equal(resolved("https://b.test/x", "https://a.test/"), "https://b.test/x");
  assert.equal(resolved("relative", undefined), "relative");
  assert.equal(resolved("x", "not a url"), "x");
});

const layer = (name: string, more: Partial<WMSLayer> = {}): WMSLayer => ({
  name, title: name, crs: ["EPSG:3857"], boundingBoxes: [], styles: [], queryable: false, opaque: false, layers: [], ...more,
});
const wms = (version: string, layers: WMSLayer[]): WMSCapabilities => ({
  service: "WMS", version, title: "t", getMapUrl: "https://a.test/wms?map=m", mapFormats: [], infoFormats: [], layers,
});

test("wmsSource asks GetMap in EPSG:3857 with the layers' bounds and attribution", () => {
  const caps = wms("1.3.0", [layer("root", { name: undefined, layers: [
    layer("a", { bounds: [0, 0, 10, 10], attribution: { title: "A" } }),
    layer("b", { bounds: [-5, 2, 3, 20], attribution: { title: "B" } }),
    layer("c", { crs: ["EPSG:4326"] }),
  ] })]);
  assert.deepEqual(allLayers(caps.layers).map((l) => l.name), [undefined, "a", "b", "c"]);
  const s = wmsSource(caps, { layers: ["a", "b"], styles: ["s1", ""], transparent: false, params: { TIME: "2020" } });
  assert.deepEqual(s, {
    type: "raster",
    tiles: ["https://a.test/wms?map=m&SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=a%2Cb&STYLES=s1%2C&FORMAT=image%2Fpng&TRANSPARENT=FALSE&WIDTH=256&HEIGHT=256&CRS=EPSG%3A3857&BBOX={bbox-epsg-3857}&TIME=2020"],
    tileSize: 256,
    bounds: [-5, 0, 10, 20],
    attribution: "A | B",
  });
  assert.match(wmsSource(wms("1.1.1", [layer("a", { crs: ["EPSG:900913"] })]), { layers: "a", tileSize: 512 }).tiles[0], /&SRS=EPSG%3A900913&BBOX=/);
  assert.throws(() => wmsSource(caps, { layers: "c" }), /not offered in EPSG:3857/);
  assert.throws(() => wmsSource(caps, { layers: "x" }), /no layer named x/);
});

const quad = (from: number, to: number, ids = (z: number) => String(z)): WMTSTileMatrixSet => ({
  id: "GoogleMapsCompatible",
  crs: "urn:ogc:def:crs:EPSG::3857",
  matrices: Array.from({ length: to - from + 1 }, (_, i) => {
    const z = from + i;
    return { id: ids(z), scale: 559082264.0287178 / 2 ** z, topLeft: [-20037508.3427892, 20037508.3427892] as [number, number], tileWidth: 256, tileHeight: 256, matrixWidth: 2 ** z, matrixHeight: 2 ** z };
  }),
});

test("mercatorZooms accepts Web Mercator's quadtree only", () => {
  assert.deepEqual(mercatorZooms(quad(0, 18)), [0, 18]);
  assert.deepEqual(mercatorZooms(quad(2, 5)), [2, 5]);
  assert.equal(mercatorZooms({ ...quad(0, 3), crs: "EPSG:4326" }), null);
  const gap = quad(0, 3);
  gap.matrices.splice(1, 1);
  assert.equal(mercatorZooms(gap), null);
  const shifted = quad(0, 3);
  shifted.matrices[2].topLeft = [0, 0];
  assert.equal(mercatorZooms(shifted), null);
  assert.equal(mercatorZooms({ ...quad(0, 0), matrices: [] }), null);
});

const wmts = (resources: { format: string; resourceType: string; template: string }[], set = quad(0, 3)): WMTSCapabilities => ({
  service: "WMTS",
  version: "1.0.0",
  title: "t",
  getTileUrl: "https://a.test/wmts?",
  tileMatrixSets: [{ ...set, id: "other", crs: "EPSG:4326" }, set],
  layers: [{
    id: "l", title: "L", bounds: [-200, -10, 10, 10], formats: ["image/png"], infoFormats: [], tileMatrixSets: ["other", "GoogleMapsCompatible"], resources,
    styles: [{ id: "plain", isDefault: false }, { id: "main", isDefault: true }], dimensions: [{ id: "Time", default: "2020-01-01", values: [] }],
  }],
});

test("wmtsSource fills a ResourceURL template, or asks GetTile by KVP", () => {
  const rest = wmtsSource(wmts([{ format: "image/png", resourceType: "tile", template: "https://a.test/{Layer}/{Style}/{Time}/{TileMatrixSet}/{TileMatrix}/{TileRow}/{TileCol}.png" }]), { layer: "l" });
  assert.deepEqual(rest, { type: "raster", tiles: ["https://a.test/{Layer}/main/2020-01-01/GoogleMapsCompatible/{z}/{y}/{x}.png"], tileSize: 256, minzoom: 0, maxzoom: 3, bounds: [-180, -10, 10, 10] });
  const kvp = wmtsSource(wmts([], quad(1, 2, (z) => `EPSG:3857:${z}`)), { layer: "l", style: "plain", dimensions: { Time: "2021" } });
  assert.equal(kvp.tiles[0], "https://a.test/wmts?SERVICE=WMTS&REQUEST=GetTile&VERSION=1.0.0&LAYER=l&STYLE=plain&FORMAT=image%2Fpng&TILEMATRIXSET=GoogleMapsCompatible&TILEMATRIX=EPSG%3A3857%3A{z}&TILEROW={y}&TILECOL={x}&Time=2021");
  assert.deepEqual([kvp.minzoom, kvp.maxzoom], [1, 2]);
  assert.throws(() => wmtsSource(wmts([]), { layer: "x" }), /no layer x/);
  assert.throws(() => wmtsSource(wmts([]), { layer: "l", tileMatrixSet: "other" }), /no Web Mercator tile matrix set named other/);
  assert.throws(() => wmtsSource(wmts([], quad(0, 10, (z) => `L${String(z).padStart(2, "0")}`)), { layer: "l" }), /not named by zoom/);
  assert.throws(() => wmtsSource({ ...wmts([]), getTileUrl: undefined }, { layer: "l" }), /no URL for image\/png/);
});

const lods = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => ({ level: from + i, resolution: 156543.03392800014 / 2 ** (from + i), scale: 591657527.591555 / 2 ** (from + i) }));
const cached: ArcGISService = {
  copyrightText: "Esri",
  singleFusedMapCache: true,
  spatialReference: { wkid: 102100, latestWkid: 3857 },
  fullExtent: { xmin: -MERCATOR_HALF, ymin: 0, xmax: 0, ymax: MERCATOR_HALF * 2 },
  tileInfo: { rows: 256, cols: 256, origin: { x: -20037508.342787, y: 20037508.342787 }, spatialReference: { wkid: 102100 }, lods: lods(0, 19) },
};

test("arcgisSource uses a Web Mercator cache, else export or exportImage", () => {
  assert.deepEqual(arcgisZooms(cached), [0, 19]);
  const bounds = arcgisBounds(cached)!;
  assert.deepEqual(bounds.map((v) => Math.round(v * 1e6) / 1e6), [-180, 0, 0, 85.051129]);
  assert.deepEqual(arcgisSource(cached, "https://a.test/arcgis/rest/services/T/MapServer/?f=json"), {
    type: "raster", tiles: ["https://a.test/arcgis/rest/services/T/MapServer/tile/{z}/{y}/{x}"], tileSize: 256, minzoom: 0, maxzoom: 19, bounds, attribution: "Esri",
  });
  assert.equal(
    arcgisSource(cached, "https://a.test/s/MapServer", { layers: [1, 2] }).tiles[0],
    "https://a.test/s/MapServer/export?bbox={bbox-epsg-3857}&bboxSR=3857&imageSR=3857&size=256%2C256&dpi=96&format=png32&transparent=true&layers=show%3A1%2C2&f=image",
  );
  assert.equal(
    arcgisSource({}, "https://a.test/s/ImageServer", { tileSize: 512, transparent: false }).tiles[0],
    "https://a.test/s/ImageServer/exportImage?bbox={bbox-epsg-3857}&bboxSR=3857&imageSR=3857&size=512%2C512&format=png&transparent=false&f=image",
  );
  assert.equal(arcgisZooms({ ...cached, tileInfo: { ...cached.tileInfo!, lods: [{ level: 0, resolution: 1000, scale: 1 }] } }), null);
  assert.equal(arcgisZooms({ ...cached, tileInfo: { ...cached.tileInfo!, origin: { x: 0, y: 0 } } }), null);
  assert.equal(arcgisZooms({ ...cached, tileInfo: { ...cached.tileInfo!, spatialReference: { wkid: 4326 } } }), null);
  assert.deepEqual(arcgisBounds({ fullExtent: { xmin: 1, ymin: 2, xmax: 3, ymax: 4, spatialReference: { wkid: 4326 } } }), [1, 2, 3, 4]);
  assert.equal(arcgisBounds({ fullExtent: { xmin: 1, ymin: 2, xmax: 3, ymax: 4, spatialReference: { wkid: 6677 } } }), undefined);
  assert.equal(arcgisBounds({}), undefined);
  assert.throws(() => arcgisSource(cached, "https://a.test/s/FeatureServer"), /not an ArcGIS MapServer, ImageServer or VectorTileServer/);
});

const vectorService: ArcGISService = {
  copyrightText: "Esri",
  tiles: ["tile/{z}/{y}/{x}.pbf"],
  maxzoom: 22,
  minLOD: 0,
  maxLOD: 16,
  spatialReference: { wkid: 102100 },
  fullExtent: cached.fullExtent,
  tileInfo: { ...cached.tileInfo!, rows: 512, cols: 512 },
};

test("arcgisSource makes a VectorTileServer's vector source with its TileJSON zooms", () => {
  const url = "https://a.test/arcgis/rest/services/B/VectorTileServer";
  const s = arcgisSource(vectorService, `${url}/`);
  assert.deepEqual(s, { type: "vector", tiles: [`${url}/tile/{z}/{y}/{x}.pbf`], minzoom: 0, maxzoom: 22, bounds: arcgisBounds(vectorService), attribution: "Esri" });
  assert.equal(s.bounds?.[0], -180);
  assert.equal(arcgisSource({ ...vectorService, maxzoom: undefined, tiles: undefined }, url).maxzoom, 16);
  const small = arcgisSource({ tileInfo: { ...cached.tileInfo!, lods: lods(0, 5) } }, url);
  assert.deepEqual([small.minzoom, small.maxzoom, small.tileSize, small.tiles[0]], [0, 5, 256, `${url}/tile/{z}/{y}/{x}.pbf`]);
});

test("arcgisVectorStyle makes Esri's relative URLs absolute and the service's source explicit", () => {
  const service = "https://a.test/arcgis/rest/services/B/VectorTileServer";
  const styleUrl = `${service}/resources/styles/root.json`;
  const style = {
    version: 8,
    sprite: "../sprites/sprite",
    glyphs: "../fonts/{fontstack}/{range}.pbf",
    sources: {
      esri: { type: "vector", url: "../../" },
      other: { type: "vector", url: "https://b.test/tiles.json" },
      local: { type: "raster", tiles: ["../t/{z}/{x}/{y}.png"] },
      inline: { type: "geojson", data: { type: "FeatureCollection", features: [] } },
    },
    layers: [{ id: "bg", type: "background" }],
  };
  const out = arcgisVectorStyle(style, styleUrl, vectorService, service);
  assert.equal(out.sprite, `${service}/resources/sprites/sprite`);
  assert.equal(out.glyphs, `${service}/resources/fonts/{fontstack}/{range}.pbf`);
  assert.deepEqual(out.sources.esri, arcgisSource(vectorService, service));
  assert.deepEqual(out.sources.other, { type: "vector", url: "https://b.test/tiles.json" });
  assert.deepEqual(out.sources.local, { type: "raster", tiles: [`${service}/resources/t/{z}/{x}/{y}.png`] });
  assert.equal(out.sources.inline, style.sources.inline);
  assert.equal(out.layers, style.layers);
  const sprites = arcgisVectorStyle({ ...style, sprite: [{ id: "a", url: "../s/a" }] }, styleUrl, vectorService, service).sprite;
  assert.deepEqual(sprites, [{ id: "a", url: `${service}/resources/s/a` }]);
});

const base = "https://api.test/collections";

test("readOGCCollections reads ids, extents and the links of each collection", () => {
  const doc = {
    collections: [{
      id: "lakes",
      title: "Lakes",
      extent: { spatial: { bbox: [[-180, -60, 0, 180, 80, 10]] } },
      crs: ["http://www.opengis.net/def/crs/OGC/1.3/CRS84", 4326],
      itemType: "feature",
      links: [
        { rel: "items", type: "text/html", href: "lakes/items?f=html" },
        { rel: "items", type: "application/geo+json", href: "lakes/items?f=json" },
        { rel: "http://www.opengis.net/def/rel/ogc/1.0/tilesets-vector", href: "lakes/tiles" },
        { rel: "map", type: "image/png", href: "lakes/map" },
        { rel: "bad", href: 3 },
        "nonsense",
      ],
    }, { id: 7, extent: { spatial: { bbox: [1, 2, 3] } } }],
  };
  assert.deepEqual(readOGCCollections(doc, base), [
    {
      id: "lakes", title: "Lakes", description: undefined, bounds: [-180, -60, 180, 80], crs: ["http://www.opengis.net/def/crs/OGC/1.3/CRS84"], itemType: "feature",
      itemsUrl: "https://api.test/lakes/items?f=json", vectorTilesUrl: "https://api.test/lakes/tiles", mapTilesUrl: undefined, mapUrl: "https://api.test/lakes/map",
    },
    { id: "7", title: undefined, description: undefined, bounds: undefined, crs: [], itemType: undefined, itemsUrl: undefined, vectorTilesUrl: undefined, mapTilesUrl: undefined, mapUrl: undefined },
  ]);
  assert.equal(readOGCCollection({ id: "x", extent: { spatial: { bbox: [0, 1, 2, 3] } } }, base).bounds?.join(), "0,1,2,3");
  assert.throws(() => readOGCCollections({}, base), /not an OGC API collections document/);
  assert.deepEqual(ogcLinks(null, base), []);
  assert.equal(ogcLink(ogcLinks({ links: [{ rel: "data", href: "a" }, { rel: "data", type: "application/json", href: "b" }] }, base), ["data"], /json/), "https://api.test/b");
});

test("OGC API tilesets on WebMercatorQuad become sources", () => {
  const list = {
    tilesets: [
      { tileMatrixSetURI: "http://www.opengis.net/def/tilematrixset/OGC/1.0/WorldCRS84Quad", links: [{ rel: "self", href: "tiles/WorldCRS84Quad" }] },
      { tileMatrixSetURI: "http://www.opengis.net/def/tilematrixset/OGC/1.0/WebMercatorQuad", links: [{ rel: "self", type: "application/json", href: "tiles/WebMercatorQuad?f=json" }] },
    ],
  };
  assert.equal(ogcTilesetUrl(list, "https://api.test/collections/lakes/tiles"), "https://api.test/collections/lakes/tiles/WebMercatorQuad?f=json");
  assert.equal(ogcTilesetUrl({ tilesets: [list.tilesets[0]] }, base), undefined);
  assert.equal(ogcTilesetUrl({}, base), undefined);
  assert.equal(isWebMercatorQuad({ links: [{ rel: "http://www.opengis.net/def/rel/ogc/1.0/tiling-scheme", href: "https://x/WebMercatorQuad" }] }), true);
  const tileset = {
    dataType: "vector",
    tileMatrixSetId: "WebMercatorQuad",
    tileMatrixSetLimits: [{ tileMatrix: "2" }, { tileMatrix: "5" }, { tileMatrix: "x" }],
    boundingBox: { lowerLeft: [-190, -10], upperRight: [10, 10], crs: "http://www.opengis.net/def/crs/OGC/1.3/CRS84" },
    links: [
      { rel: "item", type: "image/png", href: "png/{tileMatrix}/{tileRow}/{tileCol}" },
      { rel: "item", type: "application/vnd.mapbox-vector-tile", href: "https://t.test/{tileMatrix}/{tileRow}/{tileCol}?f=mvt" },
    ],
  };
  assert.deepEqual(ogcTileSource(tileset, base), { type: "vector", tiles: ["https://t.test/{z}/{y}/{x}?f=mvt"], minzoom: 2, maxzoom: 5, bounds: [-180, -10, 10, 10] });
  assert.deepEqual(ogcTileSource({ ...tileset, dataType: "map", tileMatrixSetLimits: undefined, boundingBox: undefined }, base), { type: "raster", tiles: ["https://api.test/png/{z}/{y}/{x}"] });
  assert.throws(() => ogcTileSource({ ...tileset, tileMatrixSetId: "WorldCRS84Quad" }, base), /not on WebMercatorQuad/);
  assert.throws(() => ogcTileSource({ ...tileset, links: [] }, base), /no tile URL/);
});
