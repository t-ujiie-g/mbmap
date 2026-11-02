import assert from "node:assert/strict";
import test from "node:test";
import { type GeoJSONFeature, orderRendered, queryPoints, type TileResult } from "../src/query.ts";

const f = (name: string): GeoJSONFeature => ({ type: "Feature", geometry: null, properties: { name } });
const names = (xs: { feature: GeoJSONFeature }[]) => xs.map((x) => x.feature.properties.name);

test("queryPoints: a point, a box as a closed ring, the whole map by default", () => {
  assert.deepEqual(queryPoints([3, 4], 800, 600), [3, 4]);
  assert.deepEqual(queryPoints([[1, 2], [5, 6]], 800, 600), [1, 2, 5, 2, 5, 6, 1, 6, 1, 2]);
  assert.deepEqual(queryPoints(null, 800, 600), [0, 0, 800, 0, 800, 600, 0, 600, 0, 0]);
});

test("orderRendered: top layer first, tiles by zoom, row, column, last drawn first, once per tile", () => {
  const layers = [{ id: "fill", type: "fill" }, { id: "line", type: "line" }];
  const tiles: TileResult[] = [
    { z: 14, x: 2, y: 1, hits: [{ layer: "fill", index: 1, distance: NaN, feature: f("f-b1") }] },
    {
      z: 14, x: 1, y: 1,
      hits: [
        { layer: "fill", index: 3, distance: NaN, feature: f("f-a3") },
        { layer: "line", index: 0, distance: NaN, feature: f("l-a0") },
        { layer: "fill", index: 7, distance: NaN, feature: f("f-a7") },
        { layer: "fill", index: 7, distance: NaN, feature: f("dup") },
        { layer: -1, index: 0, distance: NaN, feature: f("source") },
      ],
    },
  ];
  assert.deepEqual(names(orderRendered(tiles, layers)), ["l-a0", "f-a7", "f-a3", "f-b1"]);
  assert.deepEqual(orderRendered(tiles, layers)[0].layer, "line");
});

test("orderRendered: extrusions nearest first where the first of their layers stands", () => {
  const layers = [{ id: "low", type: "fill" }, { id: "a3d", type: "fill-extrusion" }, { id: "mid", type: "line" }, { id: "b3d", type: "fill-extrusion" }];
  const tiles: TileResult[] = [{
    z: 14, x: 0, y: 0,
    hits: [
      { layer: "a3d", index: 0, distance: 0.5, feature: f("a-near") },
      { layer: "b3d", index: 0, distance: 0.9, feature: f("b-far") },
      { layer: "mid", index: 0, distance: NaN, feature: f("mid") },
      { layer: "low", index: 0, distance: NaN, feature: f("low") },
    ],
  }];
  // At b3d the nearest extrusion (of a3d) stands lower, so none goes yet; at a3d, every
  // extrusion of a3d or above goes, nearest first.
  assert.deepEqual(names(orderRendered(tiles, layers)), ["mid", "a-near", "b-far", "low"]);
});

test("orderRendered: extrusions at one depth to rounding come as exact ties do", () => {
  const layers = [{ id: "e", type: "fill-extrusion" }];
  const tiles: TileResult[] = [{
    z: 14, x: 0, y: 0,
    hits: [
      { layer: "e", index: 2, distance: 0.7 * (1 + 1e-12), feature: f("roof") },
      { layer: "e", index: 1, distance: 0.7, feature: f("outline") },
      { layer: "e", index: 0, distance: 0.5, feature: f("near") },
    ],
  }];
  const exact = tiles.map((t) => ({ ...t, hits: t.hits.map((h) => ({ ...h, distance: Math.round(h.distance * 10) / 10 })) }));
  assert.deepEqual(names(orderRendered(tiles, layers)), names(orderRendered(exact, layers)));
  assert.deepEqual(names(orderRendered(tiles, layers)), ["near", "outline", "roof"]);
});
