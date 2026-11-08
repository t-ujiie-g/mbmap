import assert from "node:assert/strict";
import test from "node:test";
import { clusterArgs, loadOptions, sameOptions } from "../src/geojson-options.ts";

const INT32_MAX = 2 ** 31 - 1;

test("loadOptions takes MapLibre's defaults", () => {
  assert.deepEqual(loadOptions({ type: "geojson", data: {} }), { maxzoom: 18, buffer: 128, tolerance: 0.375, lineMetrics: false, cluster: null, promoteId: undefined });
  assert.deepEqual(loadOptions({ cluster: true }).cluster, { maxZoom: 17, radius: 50, minPoints: 2 });
  assert.deepEqual(loadOptions({ maxzoom: 10, buffer: 0, tolerance: 1, lineMetrics: true }), { maxzoom: 10, buffer: 0, tolerance: 1, lineMetrics: true, cluster: null, promoteId: undefined });
  assert.equal(loadOptions({ maxzoom: "12" }).maxzoom, 18);
  assert.equal(loadOptions({ promoteId: "code" }).promoteId, "code");
  assert.equal(loadOptions({ promoteId: { layer: "code" } }).promoteId, undefined);
});

test("loadOptions clamps the cluster options", () => {
  assert.deepEqual(loadOptions({ cluster: true, clusterMaxZoom: 14.4, clusterRadius: 80, clusterMinPoints: 3.2 }).cluster, { maxZoom: 14, radius: 80, minPoints: 4 });
  assert.equal(loadOptions({ cluster: true, clusterMaxZoom: 99 }).cluster?.maxZoom, 30);
  assert.equal(loadOptions({ cluster: true, maxzoom: 0 }).cluster?.maxZoom, -1);
  assert.equal(loadOptions({ cluster: true, clusterMinPoints: 1 }).cluster?.minPoints, 2);
  assert.equal(loadOptions({ cluster: true, clusterMinPoints: 1e12 }).cluster?.minPoints, INT32_MAX);
  assert.equal(loadOptions({ cluster: "yes" }).cluster, null);
});

test("sameOptions compares the data by identity and the options by value", () => {
  const data = { type: "FeatureCollection", features: [] };
  assert.equal(sameOptions({ data, maxzoom: 18 }, { data }), true);
  assert.equal(sameOptions({ data }, { data: { ...data } }), false);
  assert.equal(sameOptions({ data }, { data, cluster: true }), false);
  const sum = { sum: ["+", ["get", "n"]] };
  assert.equal(sameOptions({ data, cluster: true, clusterProperties: sum }, { data, cluster: true, clusterProperties: { ...sum } }), true);
  assert.equal(sameOptions({ data, cluster: true, clusterProperties: sum }, { data, cluster: true }), false);
  assert.equal(sameOptions({ data: "a.json" }, { data: "a.json", attribution: "x" }), true);
  assert.equal(sameOptions({ data, promoteId: "a" }, { data, promoteId: "b" }), false);
});

test("clusterArgs keeps ids in int32 and maps limits as the worker takes them", () => {
  assert.deepEqual(clusterArgs({ op: "expansion", cluster: 5 }), { op: "expansion", cluster: 5 });
  assert.deepEqual(clusterArgs({ op: "leaves", cluster: -INT32_MAX }), { op: "leaves", cluster: -INT32_MAX, limit: 10, offset: 0 });
  assert.deepEqual(clusterArgs({ op: "leaves", cluster: 1, limit: Infinity, offset: 1e12 }), { op: "leaves", cluster: 1, limit: -1, offset: INT32_MAX });
  assert.deepEqual(clusterArgs({ op: "leaves", cluster: 1, limit: 2 ** 31 }), { op: "leaves", cluster: 1, limit: -1, offset: 0 });
  assert.deepEqual(clusterArgs({ op: "leaves", cluster: 1, limit: 0 }), { op: "leaves", cluster: 1, limit: 0, offset: 0 });
});

test("clusterArgs refuses ids past int32, fractions and negative limits", () => {
  assert.throws(() => clusterArgs({ op: "children", cluster: 2 ** 31 }), /no cluster with the id/);
  assert.throws(() => clusterArgs({ op: "children", cluster: 1.5 }), /no cluster with the id/);
  assert.throws(() => clusterArgs({ op: "leaves", cluster: 1, limit: -1 }), /bad limit/);
  assert.throws(() => clusterArgs({ op: "leaves", cluster: 1, limit: 2.5 }), /bad limit/);
  assert.throws(() => clusterArgs({ op: "leaves", cluster: 1, offset: -1 }), /bad offset/);
});

test("loadOptions keeps maxzoom, buffer and tolerance within the style's ranges", () => {
  const o = loadOptions({ type: "geojson", data: {}, maxzoom: 99, buffer: 1e9, tolerance: -1 });
  assert.deepEqual([o.maxzoom, o.buffer, o.tolerance], [24, 512, 0]);
  const n = loadOptions({ type: "geojson", data: {}, maxzoom: NaN, buffer: Infinity, tolerance: NaN });
  assert.deepEqual([n.maxzoom, n.buffer, n.tolerance], [18, 128, 0.375]);
});
