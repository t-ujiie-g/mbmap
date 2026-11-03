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

test("inZoomRange and layerShown: MapLibre's isHidden, the zoom range alone or with visibility", async () => {
  const { inZoomRange, layerShown } = await import("../src/attribution.ts");
  const layer = { minzoom: 10, maxzoom: 14, layout: { visibility: "none" } };
  assert.deepEqual([9.9, 10, 13.9, 14].map((z) => inZoomRange(layer, z)), [false, true, true, false]);
  assert.equal(layerShown(layer, 12), false);
  assert.equal(layerShown({ minzoom: 10 }, 12), true);
  assert.equal(inZoomRange({}, 0), true);
});
