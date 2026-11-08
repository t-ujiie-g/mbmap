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

test("on the globe renderInput gives the globe's matrices, MapLibre's globe prelude and Mercator as fallback", () => {
  const globe = identity.map((v, i) => (i === 12 ? 0.5 : v));
  const projection = identity.map((v) => v * 2);
  const o = renderInput([...numbers, 0.75, ...globe, ...projection, 3, 40, 0.1, 0.2, 0.3, 0.4]);
  assert.deepEqual([...o.modelViewProjectionMatrix], globe);
  assert.deepEqual([...o.projectionMatrix], projection);
  assert.deepEqual([o.nearZ, o.farZ], [3, 40]);
  assert.equal(o.shaderData.variantName, "globe");
  assert.equal(o.shaderData.define, "#define GLOBE");
  assert.match(o.shaderData.vertexShaderPrelude, /uniform mat4 u_projection_matrix;\n#define GLOBE_RADIUS/);
  const d = o.defaultProjectionData;
  assert.ok(d.mainMatrix instanceof Float32Array);
  assert.deepEqual([...d.mainMatrix], globe);
  assert.deepEqual([...d.fallbackMatrix], [512, 0, 0, 0, 0, 512, 0, 0, 0, 0, 256, 0, 0, 0, 0, 1]);
  assert.deepEqual([d.projectionTransition, ...d.clippingPlane], [0.75, 0.1, 0.2, 0.3, 0.4]);
  // As MapLibre, a tile's data takes the transition only when asked to.
  const tileID = { canonical: { x: 1, y: 0, z: 1 } };
  assert.equal(o.getProjectionData({ tileID }).projectionTransition, 0);
  const t = o.getProjectionData({ tileID, applyGlobeMatrix: true });
  assert.equal(t.projectionTransition, 0.75);
  assert.equal(t.fallbackMatrix[12], 256);
  assert.deepEqual(t.tileMercatorCoords, [0.5, 0, 1 / 2 / 8192, 1 / 2 / 8192]);
});

test("renderInput gives the style's lights after the numbers, on Mercator and on the globe", () => {
  const lights = [0.2, 0.2, 0.3, 0.5, 0.5, 0.4, 0, 0.6, 0.8];
  const flat = renderInput([...numbers, ...lights]);
  assert.equal(flat.shaderData.variantName, "mercator");
  assert.deepEqual(flat.lights, { ambient: new Float64Array([0.2, 0.2, 0.3]), directional: new Float64Array([0.5, 0.5, 0.4]), direction: new Float64Array([0, 0.6, 0.8]) });
  const globe = renderInput([...numbers, 0.5, ...identity, ...identity, 3, 40, 0, 0, 0, 0, ...lights]);
  assert.equal(globe.defaultProjectionData.projectionTransition, 0.5);
  assert.deepEqual(globe.lights?.direction, new Float64Array([0, 0.6, 0.8]));
  assert.equal(renderInput(numbers).lights, undefined);
});
