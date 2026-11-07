import assert from "node:assert/strict";
import test from "node:test";
import { srsNorthFirst } from "../src/services/gml.ts";
import { arcgisFormat, arcgisQueryUrl, gather, gmlFormat, geojsonFormat, MAX_PAGES, ogcItemsUrl, pageFeatures, wfsFeatureUrl } from "../src/services/features.ts";

const query = (url: string) => Object.fromEntries(new URL(url).searchParams);

test("ogcItemsUrl adds the bbox, limit, datetime and properties", () => {
  assert.equal(ogcItemsUrl("https://a.test/collections/lakes/items"), "https://a.test/collections/lakes/items");
  assert.deepEqual(query(ogcItemsUrl("https://a.test/items?f=json", { bbox: [1, 2, 3, 4], limit: 10, datetime: "2020-01-01/..", properties: ["a", "b"] })), {
    f: "json", bbox: "1,2,3,4", limit: "10", datetime: "2020-01-01/..", properties: "a,b",
  });
});

test("wfsFeatureUrl follows each version's names and the bbox's axis order", () => {
  assert.deepEqual(query(wfsFeatureUrl("https://a.test/wfs?map=m", "2.0.0", { typeName: "t", bbox: [139, 35, 140, 36], count: 10, startIndex: 20, outputFormat: "application/json" })), {
    map: "m", SERVICE: "WFS", VERSION: "2.0.0", REQUEST: "GetFeature", TYPENAMES: "t", OUTPUTFORMAT: "application/json", COUNT: "10", STARTINDEX: "20",
    BBOX: "35,139,36,140,urn:ogc:def:crs:EPSG::4326",
  });
  assert.deepEqual(query(wfsFeatureUrl("https://a.test/wfs", "1.1.0", { typeName: "t", count: 5, startIndex: 0, crs: "EPSG:4326" })), {
    SERVICE: "WFS", VERSION: "1.1.0", REQUEST: "GetFeature", TYPENAME: "t", MAXFEATURES: "5", SRSNAME: "EPSG:4326",
  });
  assert.equal(query(wfsFeatureUrl("https://a.test/wfs", "1.0.0", { typeName: "t", bbox: [139, 35, 140, 36] })).BBOX, "139,35,140,36");
});

test("geojsonFormat prefers a GeoJSON format to other JSON", () => {
  assert.equal(geojsonFormat(["text/xml; subtype=gml/3.2.1", "application/json; subtype=geojson", "json"]), "application/json; subtype=geojson");
  assert.equal(geojsonFormat(["GML2", "json"]), "json");
  assert.equal(geojsonFormat(["application/geo+json"]), "application/geo+json");
  assert.equal(geojsonFormat(["GML2"]), undefined);
});

test("arcgisQueryUrl asks GeoJSON in EPSG:4326 within an envelope", () => {
  assert.deepEqual(query(arcgisQueryUrl("https://a.test/rest/services/S/FeatureServer/0/?token=x", { bbox: [1, 2, 3, 4], outFields: ["NAME"], offset: 10, count: 5 })), {
    where: "1=1", outFields: "NAME", geometry: "1,2,3,4", geometryType: "esriGeometryEnvelope", inSR: "4326", spatialRel: "esriSpatialRelIntersects",
    outSR: "4326", resultOffset: "10", resultRecordCount: "5", f: "geojson",
  });
  assert.deepEqual(query(arcgisQueryUrl("https://a.test/S/MapServer/1", { where: "POP > 10" }, "pbf")), { where: "POP > 10", outFields: "*", outSR: "4326", f: "pbf" });
});

test("pageFeatures takes a page's features and refuses anything else", () => {
  assert.deepEqual(pageFeatures({ type: "FeatureCollection", features: [1] }, "x"), [1]);
  assert.throws(() => pageFeatures({ error: { code: 400, message: "bad where" } }, "q"), /q: ArcGIS error 400: bad where/);
  assert.throws(() => pageFeatures({ type: "Feature" }, "q"), /did not answer with GeoJSON features/);
  assert.throws(() => pageFeatures(null, "q"), /did not answer with GeoJSON features/);
});

test("gather follows pages until there is no next, a cap or a loop", async () => {
  const pages: Record<string, unknown> = {
    a: { features: [1, 2], next: "b" },
    b: { features: [3, 4], next: "c" },
    c: { features: [5] },
    loop: { features: [9], next: "loop" },
    empty: { features: [], next: "a" },
  };
  const load = async (u: string) => pages[u];
  const next = (p: unknown) => (p as { next?: string }).next;
  assert.deepEqual(await gather("a", load, next, 100, "t"), { type: "FeatureCollection", features: [1, 2, 3, 4, 5] });
  assert.deepEqual(await gather("a", load, next, 3, "t"), { type: "FeatureCollection", features: [1, 2, 3], exceeded: true });
  assert.deepEqual(await gather("a", load, next, 5, "t"), { type: "FeatureCollection", features: [1, 2, 3, 4, 5] });
  assert.deepEqual(await gather("loop", load, next, 100, "t"), { type: "FeatureCollection", features: [9], exceeded: true });
  assert.deepEqual(await gather("empty", load, next, 100, "t"), { type: "FeatureCollection", features: [] });
  let n = 0;
  const endless = await gather("p0", async () => ({ features: [n] }), () => `p${++n}`, Infinity, "t");
  assert.equal(endless.features.length, MAX_PAGES);
  assert.equal(endless.exceeded, true);
});

test("arcgisFormat prefers PBF, then GeoJSON, then JSON among a layer's query formats", () => {
  assert.equal(arcgisFormat({ supportedQueryFormats: "JSON, geoJSON, PBF" }), "pbf");
  assert.equal(arcgisFormat({ supportedQueryFormats: "JSON, geoJSON" }), "geojson");
  assert.equal(arcgisFormat({ supportedQueryFormats: "JSON" }), "json");
  assert.equal(arcgisFormat({}), "json");
  assert.equal(arcgisFormat(null), "json");
});

test("gmlFormat picks the latest GML among the formats", () => {
  assert.equal(gmlFormat(["application/json", "text/xml; subtype=gml/2.1.2", "text/xml; subtype=gml/3.1.1", "application/gml+xml; version=3.2"]), "application/gml+xml; version=3.2");
  assert.equal(gmlFormat(["GML2", "GML3"]), "GML3");
  assert.equal(gmlFormat(["application/json"]), undefined);
});

test("srsNorthFirst reads URNs and URLs by the CRS, GML 2 URLs east first, a bare code as asked", () => {
  assert.deepEqual(
    ["urn:ogc:def:crs:EPSG::4326", "http://www.opengis.net/def/crs/EPSG/0/4326", "urn:ogc:def:crs:OGC:1.3:CRS84", "http://www.opengis.net/gml/srs/epsg.xml#4326", "EPSG:4326"].map((s) => srsNorthFirst(s, false)),
    [true, true, false, false, false],
  );
  assert.equal(srsNorthFirst("EPSG:4326", true), true);
  assert.equal(srsNorthFirst("EPSG:32654", true), false);
});
