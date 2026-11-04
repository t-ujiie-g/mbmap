import assert from "node:assert/strict";
import test from "node:test";
import { filterText, resolveTiles, splitGeoJSON } from "../src/engine-style.ts";
import type { StyleSpecification } from "../src/style.ts";

const base = new URL("https://example.com/styles/style.json");

test("resolveTiles resolves tile templates against the style URL and keeps the placeholders", () => {
  const style: StyleSpecification = {
    version: 8,
    sources: {
      v: { type: "vector", tiles: ["../tiles/{z}/{x}/{y}.pbf", 7] },
      p: { type: "vector", tiles: ["pmtiles://data/a.pmtiles/{z}/{x}/{y}"] },
      u: { type: "vector", url: "a.json" },
    },
    layers: [],
  };
  const out = resolveTiles(style, base);
  assert.deepEqual(out.sources.v, { type: "vector", tiles: ["https://example.com/tiles/{z}/{x}/{y}.pbf", 7] });
  assert.deepEqual(out.sources.p, { type: "vector", tiles: ["pmtiles://https://example.com/styles/data/a.pmtiles/{z}/{x}/{y}"] });
  assert.equal(out.sources.u, style.sources.u);
  assert.deepEqual(style.sources.v, { type: "vector", tiles: ["../tiles/{z}/{x}/{y}.pbf", 7] });
});

test("resolveTiles refuses tile templates that are not http(s)", () => {
  const style: StyleSpecification = { version: 8, sources: { v: { type: "vector", tiles: ["data:,x"] } }, layers: [] };
  assert.throws(() => resolveTiles(style, base), /tiles must be an http\(s\) URL/);
});

test("splitGeoJSON lists the GeoJSON sources and leaves their data out of the style", () => {
  const data = { type: "FeatureCollection", features: [] };
  const style: StyleSpecification = {
    version: 8,
    sources: { g: { type: "geojson", data, cluster: true }, v: { type: "vector", tiles: [] } },
    layers: [{ id: "x", type: "circle", source: "g" }],
  };
  const [found, rest] = splitGeoJSON(style);
  assert.deepEqual(found, [{ id: "g", spec: { type: "geojson", data, cluster: true } }]);
  assert.deepEqual(rest.sources.g, { type: "geojson", data: null, cluster: true });
  assert.equal(rest.sources.v, style.sources.v);
  assert.equal(rest.layers, style.layers);
  assert.equal((style.sources.g as { data: unknown }).data, data);
});

test("filterText: empty for no filter, JSON otherwise, legacy filters converted only when a converter is given", () => {
  assert.equal(filterText(undefined, null), "");
  assert.equal(filterText(["==", ["get", "a"], 1], null), '["==",["get","a"],1]');
  const legacy = ["==", "a", 1];
  assert.equal(filterText(legacy, null), '["==","a",1]');
  assert.equal(filterText(legacy, () => ["converted"]), '["converted"]');
  assert.equal(filterText(["==", ["get", "a"], 1], () => ["converted"]), '["==",["get","a"],1]');
});
