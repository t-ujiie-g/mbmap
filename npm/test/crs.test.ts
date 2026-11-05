import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import test from "node:test";
import { crsArg } from "../src/crs.ts";

// The build makes projstring.ts a file of its own, which crs.ts imports as `./projstring.js`.
registerHooks({ resolve: (specifier, context, next) => next(specifier.replace(/^\.\/projstring\.js$/, "./projstring.ts"), context) });

test("crsArg takes EPSG codes in their forms", async () => {
  assert.equal(await crsArg(6677, "data"), 6677);
  assert.equal(await crsArg("6677", "data"), 6677);
  assert.equal(await crsArg("EPSG:6677", "data"), 6677);
  assert.equal(await crsArg("epsg:6677", "data"), 6677);
  assert.equal(await crsArg(" EPSG:6677 ", "data"), 6677);
  assert.equal(await crsArg("urn:ogc:def:crs:EPSG::6677", "data"), 6677);
});

test("crsArg reads CRS84 as 4326", async () => {
  assert.equal(await crsArg("CRS84", "data"), 4326);
  assert.equal(await crsArg("OGC:CRS84", "data"), 4326);
  assert.equal(await crsArg("ogc:crs84", "data"), 4326);
});

test("crsArg parses PROJ strings into a definition", async () => {
  const definition = await crsArg("+proj=longlat +ellps=GRS80", "data");
  assert.ok(definition instanceof Float64Array);
  assert.equal(definition.length, 34);
});

test("crsArg looks names up, ahead of the codes", async () => {
  const named = new Map([["TOKYO", "+proj=longlat +ellps=bessel"], ["6677", "+proj=longlat +ellps=GRS80"]]);
  assert.ok((await crsArg("tokyo", "analysis", named)) instanceof Float64Array);
  assert.ok((await crsArg("6677", "analysis", named)) instanceof Float64Array);
  assert.equal(await crsArg("EPSG:6677", "analysis", named), 6677);
});

test("crsArg refuses anything else, naming the entry", async () => {
  for (const bad of [0, -1, 1.5, NaN, "", "tokyo", "EPSG:", "EPSG:1234567", "EPSG:66.77"]) {
    await assert.rejects(crsArg(bad, "data"), /^Error: mbmap: data: not a CRS: /);
  }
  await assert.rejects(crsArg(null as unknown as string, "analysis"), /^Error: mbmap: analysis: not a CRS: null$/);
});
