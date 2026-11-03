import assert from "node:assert/strict";
import test from "node:test";
import { attributionsOf } from "../src/attribution.ts";

const style = {
  sources: {
    a: { attribution: "Long source A" },
    b: { attribution: "B" },
    c: { attribution: "source A" },
    dem: { attribution: "DEM" },
    unused: { attribution: "never" },
    blank: { attribution: "  " },
  },
  layers: [
    { id: "a", source: "a" },
    { id: "b", source: "b", minzoom: 10 },
    { id: "c", source: "c", maxzoom: 14 },
    { id: "hidden", source: "unused", layout: { visibility: "none" } },
    { id: "blank", source: "blank" },
  ],
  terrain: { source: "dem" },
};

test("attributionsOf: sources of layers shown at the zoom and of the terrain, shortest first", () => {
  assert.deepEqual(attributionsOf(style, 12), ["B", "DEM", "Long source A"]);
});

test("attributionsOf: a layer outside its zoom range leaves its source out", () => {
  assert.deepEqual(attributionsOf(style, 8), ["DEM", "Long source A"]);
  assert.deepEqual(attributionsOf(style, 14), ["B", "DEM", "Long source A"]);
  assert.deepEqual(attributionsOf({}, 3), []);
});
