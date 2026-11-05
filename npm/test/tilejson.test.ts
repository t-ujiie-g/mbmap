import assert from "node:assert/strict";
import test from "node:test";
import { tileJSONUrls, withoutSources } from "../src/tilejson.ts";
import { withTileJSON } from "../src/tilejson-merge.ts";
import { resolveTemplate } from "../src/urls.ts";

const base = new URL("https://example.com/styles/style.json");
const style = () => ({
  version: 8 as const,
  sources: {
    v: { type: "vector", url: "../tiles.json", maxzoom: 12 },
    r: { type: "raster", url: "https://other.org/r.json" },
    own: { type: "vector", url: "x.json", tiles: ["https://t/{z}/{x}/{y}.pbf"] },
    g: { type: "geojson", data: "d.json" },
  },
  layers: [
    { id: "a", type: "line", source: "v" },
    { id: "b", type: "raster", source: "r" },
  ],
});

test("tileJSONUrls lists the url sources without tiles, absolute and http(s) only", () => {
  assert.deepEqual([...tileJSONUrls(style(), base)], [["v", "https://example.com/tiles.json"], ["r", "https://other.org/r.json"]]);
  assert.throws(() => tileJSONUrls({ version: 8, sources: { x: { type: "vector", url: "file:///etc/x.json" } }, layers: [] }, base), /url must be an http\(s\) URL/);
});

test("withTileJSON merges documents (the source's own keys win) and leaves out sources still loading", () => {
  const docs = new Map<string, unknown>([
    ["https://example.com/tiles.json", { tiles: ["v/{z}/{x}/{y}.pbf"], minzoom: 2, maxzoom: 14, attribution: "© V", bounds: [1, 2, 3, 4], vector_layers: [] }],
  ]);
  const out = withTileJSON(style(), tileJSONUrls(style(), base), docs, resolveTemplate);
  assert.deepEqual(out.sources.v, { tiles: ["https://example.com/v/{z}/{x}/{y}.pbf"], minzoom: 2, maxzoom: 12, attribution: "© V", bounds: [1, 2, 3, 4], type: "vector" });
  assert.equal("r" in out.sources, false);
  assert.deepEqual(out.layers.map((l) => (l as { id: string }).id), ["a"]);
  assert.deepEqual(out.sources.own, style().sources.own);
});

test("withoutSources drops the sources and their layers, and keeps the style without any", () => {
  const out = withoutSources(style(), new Set(["v", "r"]));
  assert.deepEqual(Object.keys(out.sources), ["own", "g"]);
  assert.deepEqual(out.layers, []);
  const same = withoutSources(style(), new Set());
  assert.deepEqual(same, style());
});

test("a geotiff source's document is its file's, keyed apart from TileJSON, and merges without tiles", () => {
  const s = { version: 8 as const, sources: { cog: { type: "geotiff", url: "dem.tif", dem: true, maxzoom: 12 } }, layers: [{ id: "h", type: "hillshade", source: "cog" }] };
  const urls = tileJSONUrls(s, base);
  assert.deepEqual([...urls], [["cog", "geotiff:https://example.com/styles/dem.tif"]]);
  const docs = new Map<string, unknown>([["geotiff:https://example.com/styles/dem.tif", { bounds: [138, 35, 139, 36], minzoom: 0, maxzoom: 14, crs: 3857, range: [0, 3776] }]]);
  assert.deepEqual(withTileJSON(s, urls, docs, resolveTemplate).sources.cog, { minzoom: 0, maxzoom: 12, bounds: [138, 35, 139, 36], type: "geotiff", dem: true });
});
