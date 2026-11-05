import assert from "node:assert/strict";
import test from "node:test";
import { bboxArg, csvArgs, csvWriteArgs, formatOf, shapefileParts } from "../src/data-format.ts";

test("formatOf reads the format from a name's extension, in any case", () => {
  assert.equal(formatOf("points.CSV"), "csv");
  assert.equal(formatOf("/data/x.tsv"), "csv");
  assert.equal(formatOf("a.txt"), "csv");
  assert.equal(formatOf("shapes.wkt"), "wkt");
  assert.equal(formatOf("dump.ewkb"), "wkb");
  assert.equal(formatOf("x.wkb"), "wkb");
  assert.equal(formatOf("roads.SHP"), "shapefile");
  assert.equal(formatOf("roads.zip"), "shapefile");
  assert.equal(formatOf("world.topojson"), "topojson");
  assert.equal(formatOf("world.json"), null);
  assert.equal(formatOf("doc.kml"), "kml");
  assert.equal(formatOf("https://example.com/a.KMZ"), "kml");
  assert.equal(formatOf("run.gpx"), "gpx");
  assert.equal(formatOf("x.geojson"), "geojson");
  assert.equal(formatOf("x.FGB"), "flatgeobuf");
  assert.equal(formatOf("x.constructor"), null);
  assert.equal(formatOf("noextension"), null);
});

test("csvArgs gives the worker's defaults and character codes", () => {
  assert.deepEqual(csvArgs({}), { delimiter: -1, header: true, dynamicTyping: true, latitude: undefined, longitude: undefined, geometry: undefined });
  assert.equal(csvArgs({ delimiter: "\t" }).delimiter, 9);
  assert.deepEqual(csvArgs({ latitude: "緯度", longitude: "経度", header: false, dynamicTyping: false }), {
    delimiter: -1, header: false, dynamicTyping: false, latitude: "緯度", longitude: "経度", geometry: undefined,
  });
});

test("csvArgs refuses invalid options", () => {
  for (const bad of [{ delimiter: ";;" }, { delimiter: '"' }, { delimiter: "\n" }, { delimiter: "、" }, { delimiter: "" }]) {
    assert.throws(() => csvArgs(bad), /invalid delimiter/);
  }
  assert.throws(() => csvArgs({ header: "yes" as unknown as boolean }), /invalid header/);
  assert.throws(() => csvArgs({ dynamicTyping: 1 as unknown as boolean }), /invalid dynamicTyping/);
  assert.throws(() => csvArgs({ geometry: "" }), /invalid geometry column/);
  assert.throws(() => csvArgs({ latitude: "lat" }), /latitude and longitude go together/);
});

test("shapefileParts picks a shapefile's files by their extensions", () => {
  const f = (name: string) => ({ name });
  const parts = shapefileParts([f("a.SHP"), f("a.dbf"), f("a.prj"), f("a.cpg"), f("a.shx"), f("b.shp"), f("notes.txt")]);
  assert.deepEqual(parts, { shp: f("a.SHP"), dbf: f("a.dbf"), prj: f("a.prj"), cpg: f("a.cpg") });
  assert.equal(shapefileParts([f("a.dbf"), f("a.prj")]), null);
});

test("csvWriteArgs gives the worker's character codes and refuses invalid options", () => {
  assert.deepEqual(csvWriteArgs({}), { delimiter: 44, header: true, geometryFormat: undefined, geometry: undefined, longitude: undefined, latitude: undefined });
  assert.deepEqual(csvWriteArgs({ delimiter: "\t", header: false, geometryFormat: "lonlat", longitude: "経度", latitude: "緯度" }), {
    delimiter: 9, header: false, geometryFormat: "lonlat", geometry: undefined, longitude: "経度", latitude: "緯度",
  });
  for (const bad of [{ delimiter: ";;" }, { delimiter: '"' }, { delimiter: "\r" }, { delimiter: "、" }]) {
    assert.throws(() => csvWriteArgs(bad), /invalid delimiter/);
  }
  assert.throws(() => csvWriteArgs({ header: 1 as unknown as boolean }), /invalid header/);
  assert.throws(() => csvWriteArgs({ geometryFormat: "geojson" as "wkt" }), /invalid geometryFormat/);
  assert.throws(() => csvWriteArgs({ geometry: "a\0b" }), /invalid geometry column/);
  assert.throws(() => csvWriteArgs({ latitude: "" }), /invalid latitude column/);
});

test("bboxArg takes four finite numbers, min at most max", () => {
  assert.deepEqual(bboxArg([139, 35, 140, 36]), [139, 35, 140, 36]);
  for (const bad of [[0, 0, 1], [1, 0, 0, 1], [0, 0, Infinity, 1], "0,0,1,1"]) assert.throws(() => bboxArg(bad), /invalid bbox/);
});
