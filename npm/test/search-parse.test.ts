import assert from "node:assert/strict";
import test from "node:test";
import { parseLngLat, parsePlaneRectangular, parseUtm } from "../src/search/parse.ts";
import { matchRank, normalize } from "../src/search/dataset.ts";

test("parseLngLat: decimal degrees in both orders where both are places", () => {
  assert.deepEqual(parseLngLat("35.6812, 139.7671"), [{ lat: 35.6812, lng: 139.7671 }]);
  assert.deepEqual(parseLngLat("139.7671 35.6812"), [{ lat: 35.6812, lng: 139.7671 }]);
  assert.deepEqual(parseLngLat("10, 20"), [{ lat: 10, lng: 20 }, { lat: 20, lng: 10 }]);
  assert.deepEqual(parseLngLat("３５．６８１２，１３９．７６７１"), [{ lat: 35.6812, lng: 139.7671 }]);
  assert.deepEqual(parseLngLat("95, 200"), []);
  assert.deepEqual(parseLngLat("Tokyo"), []);
});

test("parseLngLat: degrees, minutes and seconds with hemisphere letters or 度分秒", () => {
  const near = (p: { lat: number; lng: number }, lat: number, lng: number) => Math.abs(p.lat - lat) < 1e-9 && Math.abs(p.lng - lng) < 1e-9;
  const [a] = parseLngLat("35°40′52.32″N 139°46′1.56″E");
  assert.ok(near(a, 35.6812, 139.7671));
  const [b] = parseLngLat("139°46'1.56\"E, 35°40'52.32\"N");
  assert.ok(near(b, 35.6812, 139.7671));
  const [c] = parseLngLat("北緯35度40分52.32秒 東経139度46分1.56秒".replace("北緯", "N").replace("東経", "E"));
  assert.ok(near(c, 35.6812, 139.7671));
  const [d] = parseLngLat("33°27'S 70°40'W");
  assert.ok(near(d, -33.45, -70 - 40 / 60));
  assert.deepEqual(parseLngLat("35°70′N 139°E"), []);
});

test("parsePlaneRectangular: zone in Roman or Arabic numerals, X north and Y east", () => {
  assert.deepEqual(parsePlaneRectangular("第IX系 X -35367.23 Y -5995.19"), { epsg: 6677, x: -5995.19, y: -35367.23, title: "第IX系" });
  assert.deepEqual(parsePlaneRectangular("9系 Y=-5995.19, X=-35367.23"), { epsg: 6677, x: -5995.19, y: -35367.23, title: "第IX系" });
  assert.equal(parsePlaneRectangular("第XX系 X 1 Y 2"), null);
  assert.equal(parsePlaneRectangular("第IX系 hello"), null);
});

test("parseUtm: zone, hemisphere, easting and northing", () => {
  assert.deepEqual(parseUtm("54N 388708 3949480"), { epsg: 32654, x: 388708, y: 3949480, title: "UTM 54N" });
  assert.deepEqual(parseUtm("19s 345000, 6300000"), { epsg: 32719, x: 345000, y: 6300000, title: "UTM 19S" });
  assert.equal(parseUtm("61N 1 2"), null);
});

test("normalize and matchRank: width, case and kana folded; equal, prefix, contains", () => {
  assert.equal(normalize("ＴＯＫＹＯ　トウキョウ"), "tokyo とうきょう");
  assert.equal(normalize("ｶﾞｲｴﾝ"), "がいえん");
  assert.deepEqual(["東京駅", "東京駅前", "新東京駅", "大阪"].map((t) => matchRank(normalize(t), normalize("東京駅"))), [3, 2, 1, 0]);
});

test("datasetSearch: equal names first, then prefixes, then the rest; areas keep their box", async () => {
  const { datasetSearch } = await import("../src/search/dataset.ts");
  const point = (name: string, lng: number, lat: number) => ({ properties: { name }, geometry: { type: "Point", coordinates: [lng, lat] } });
  const data = {
    features: [
      point("新東京駅", 1, 1),
      point("東京駅前", 2, 2),
      { properties: { name: "東京駅" }, geometry: { type: "Polygon", coordinates: [[[10, 20], [12, 20], [12, 24], [10, 20]]] } },
      point("大阪駅", 3, 3),
      { properties: { name: "東京駅" }, geometry: null },
    ],
  };
  const search = datasetSearch(() => data, { fields: ["name"] });
  const request = { signal: new AbortController().signal, bbox: null, limit: 8 };
  const results = await search.search("とうきょう", request);
  assert.deepEqual(results, []);
  const found = await search.search("東京駅", request);
  assert.deepEqual(found.map((r) => r.label), ["東京駅", "東京駅前", "新東京駅"]);
  assert.deepEqual(found[0].bbox, [10, 20, 12, 24]);
  assert.deepEqual(found[0].lngLat, { lng: 11, lat: 22 });
  assert.equal(found[1].bbox, undefined);
  assert.deepEqual((await search.search("東京", { ...request, limit: 2 })).length, 2);
});
