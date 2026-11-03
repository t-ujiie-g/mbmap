import assert from "node:assert/strict";
import test from "node:test";
import { renderInput } from "../src/custom.ts";

// The engine's numbers for an identity model-view-projection, a world 512 px wide and 2 px per meter.
const identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
const numbers = [...identity, ...identity, 0.6435011087932844, 12, 900, 512, 2];

test("renderInput gives MapLibre's matrices: world pixels and meters, and Mercator in mainMatrix", () => {
  const o = renderInput(numbers);
  assert.deepEqual([...o.modelViewProjectionMatrix], identity);
  assert.deepEqual([o.fov, o.nearZ, o.farZ], [0.6435011087932844, 12, 900]);
  // Mercator x, y and z in the same units: z scaled by the world size over pixels per meter.
  assert.deepEqual([...o.defaultProjectionData.mainMatrix], [512, 0, 0, 0, 0, 512, 0, 0, 0, 0, 256, 0, 0, 0, 0, 1]);
  assert.deepEqual(o.defaultProjectionData.tileMercatorCoords, [0, 0, 1, 1]);
  assert.match(o.shaderData.vertexShaderPrelude, /vec4 projectTile\(vec2 p\)/);
  assert.equal(o.shaderData.define, "#define PROJECTION_MERCATOR");
});

test("getProjectionData takes a tile's 8192 units to world pixels", () => {
  const o = renderInput(numbers);
  const t = o.getProjectionData({ tileID: { canonical: { x: 1, y: 0, z: 1 } } });
  // Tile 1/1/0 spans x 256..512, y 0..256 of the 512 px world.
  assert.deepEqual([...t.mainMatrix], [256 / 8192, 0, 0, 0, 0, 256 / 8192, 0, 0, 0, 0, 1, 0, 256, 0, 0, 1]);
  assert.deepEqual(t.tileMercatorCoords, [0.5, 0, 1 / 2 / 8192, 1 / 2 / 8192]);
  assert.deepEqual([...o.getProjectionData({ tileID: null }).mainMatrix], identity);
});
