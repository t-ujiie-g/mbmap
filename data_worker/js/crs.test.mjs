import assert from "node:assert/strict";
import test from "node:test";
import { toLonLat, transformPairs } from "./crs.mjs";

const PAGE = 1024;
const OUT = 512 * 1024;
const encoder = new TextEncoder();

// proj.wasm's exports: `crs_kind` refuses the codes in `unknown`, handles start at 0, and
// `transform_coords` adds `from` to x and `to` to y, or gives NaN for x at or past `reach`.
function fakeProj({ unknown = [], reach = Infinity } = {}) {
  const memory = { buffer: new ArrayBuffer(1024 * 1024) };
  const log = { definitions: [], transforms: [] };
  let len = 0;
  const refuse = (message) => {
    const error = encoder.encode(message);
    new Uint8Array(memory.buffer, OUT, error.length).set(error);
    return -error.length;
  };
  return {
    log,
    memory,
    prepare_input(n) {
      len = n;
      return PAGE;
    },
    output_addr: () => OUT,
    crs_kind: (code) => (unknown.includes(code) ? refuse(`unknown EPSG code ${code}`) : 0),
    define_crs() {
      log.definitions.push(Array.from(new Float64Array(memory.buffer, PAGE, len / 8)));
      return log.definitions.length - 1;
    },
    transform_coords(from, to) {
      log.transforms.push([from, to]);
      const input = new Float64Array(memory.buffer, PAGE, len / 8);
      const out = new Float64Array(memory.buffer, OUT, len / 8);
      for (let i = 0; i < input.length; i += 2) {
        out[i] = input[i] >= reach ? NaN : input[i] + from;
        out[i + 1] = input[i + 1] + to;
      }
      return input.length;
    },
  };
}

// Table bytes (docs/FORMATS.md "Table") of `rows`: a list of [x, y] points each, an empty one without geometry.
function table(rows) {
  const f = rows.length;
  const filled = rows.filter((row) => row.length > 0);
  const [p, r] = [filled.length, filled.length];
  const n = filled.reduce((sum, row) => sum + row.length, 0);
  const ends = 20 + ((f + 3) & ~3);
  const coordsAt = ends + (f + p + r) * 4;
  const bytes = new ArrayBuffer(coordsAt + n * 16);
  const v = new DataView(bytes);
  [f, p, r, n].forEach((word, i) => v.setUint32(i * 4, word, true));
  let [part, point] = [0, 0];
  rows.forEach((row, i) => {
    if (row.length > 0) {
      for (const [x, y] of row) {
        v.setFloat64(coordsAt + point * 16, x, true);
        v.setFloat64(coordsAt + point * 16 + 8, y, true);
        point++;
      }
      v.setUint32(ends + (f + part) * 4, part + 1, true);
      v.setUint32(ends + (f + p + part) * 4, point, true);
      part++;
    }
    v.setUint32(ends + i * 4, part, true);
  });
  return { bytes, coords: () => Array.from({ length: n }, (_, i) => [v.getFloat64(coordsAt + i * 16, true), v.getFloat64(coordsAt + i * 16 + 8, true)]) };
}

const loaded = (exports) => async () => exports;
const untouched = async () => {
  throw new Error("proj.wasm loaded");
};
const slots = (first) => Float64Array.from({ length: 34 }, (_, i) => (i === 0 ? first : NaN));

test("toLonLat takes every row from the fallback when there are no SRIDs", async () => {
  const proj = fakeProj();
  const t = table([[[1, 2], [3, 4]], [[5, 6]]]);
  assert.equal(await toLonLat(t.bytes, null, 6677, loaded(proj)), t.bytes);
  assert.deepEqual(t.coords(), [[6678, 4328], [6680, 4330], [6682, 4332]]);
  assert.deepEqual(proj.log.transforms, [[6677, 4326]]);
});

test("toLonLat prefers a row's SRID over the fallback", async () => {
  const proj = fakeProj();
  const t = table([[[1, 2]], [[3, 4]]]);
  await toLonLat(t.bytes, Int32Array.of(2451, 2451), 6677, loaded(proj));
  assert.deepEqual(t.coords(), [[2452, 4328], [2454, 4330]]);
  assert.deepEqual(proj.log.transforms, [[2451, 4326]]);
});

test("toLonLat treats mixed rows apart and leaves those in 4326", async () => {
  const proj = fakeProj();
  const t = table([[[1, 2]], [[3, 4]], [], [[5, 6]], [[7, 8]]]);
  await toLonLat(t.bytes, Int32Array.of(6677, 4326, 2451, 0, 6677), 2443, loaded(proj));
  assert.deepEqual(t.coords(), [[6678, 4328], [3, 4], [2448, 4332], [6684, 4334]]);
  assert.deepEqual(proj.log.transforms, [[6677, 4326], [2443, 4326]]);
});

test("toLonLat leaves rows without an SRID when there is no fallback", async () => {
  const proj = fakeProj();
  const t = table([[[1, 2]], [[3, 4]]]);
  await toLonLat(t.bytes, Int32Array.of(0, 6677), undefined, loaded(proj));
  assert.deepEqual(t.coords(), [[1, 2], [6680, 4330]]);
});

test("toLonLat changes nothing and loads nothing when all is in 4326", async () => {
  const t = table([[[1, 2]], [[3, 4]]]);
  await toLonLat(t.bytes, null, undefined, untouched);
  await toLonLat(t.bytes, null, 4326, untouched);
  await toLonLat(t.bytes, Int32Array.of(4326, 4326), 6677, untouched);
  await toLonLat(t.bytes, Int32Array.of(4326, 0), 4326, untouched);
  assert.deepEqual(t.coords(), [[1, 2], [3, 4]]);
});

test("toLonLat refuses coordinates out of reach, naming the SRID", async () => {
  const far = () => fakeProj({ reach: 100 });
  await assert.rejects(toLonLat(table([[[1, 2]], [[200, 4]]]).bytes, Int32Array.of(6677, 6677), undefined, loaded(far())), /^Error: coordinates out of reach of SRID 6677$/);
  await assert.rejects(toLonLat(table([[[200, 2]]]).bytes, null, 6677, loaded(far())), /^Error: coordinates out of reach of the CRS$/);
});

test("toLonLat names the SRID an unknown code came from, and only then", async () => {
  const unknown = () => fakeProj({ unknown: [9999] });
  await assert.rejects(toLonLat(table([[[1, 2]]]).bytes, Int32Array.of(9999), undefined, loaded(unknown())), /^Error: SRID 9999: unknown EPSG code 9999$/);
  await assert.rejects(toLonLat(table([[[1, 2]]]).bytes, null, 9999, loaded(unknown())), /^Error: unknown EPSG code 9999$/);
});

test("a .prj's { code, definition } goes by its code if known, else its definition", async () => {
  const known = fakeProj();
  await toLonLat(table([[[1, 2]]]).bytes, null, { code: 6677, definition: slots(1) }, loaded(known));
  assert.deepEqual(known.log.transforms, [[6677, 4326]]);
  assert.deepEqual(known.log.definitions, []);
  const other = fakeProj({ unknown: [6677] });
  await toLonLat(table([[[1, 2]]]).bytes, null, { code: 6677, definition: slots(1) }, loaded(other));
  assert.deepEqual(other.log.transforms, [[-1, 4326]]);
  assert.equal(other.log.definitions.length, 1);
  const only = fakeProj();
  await toLonLat(table([[[1, 2]]]).bytes, null, { definition: slots(1) }, loaded(only));
  assert.deepEqual(only.log.transforms, [[-1, 4326]]);
  await assert.rejects(toLonLat(table([[[1, 2]]]).bytes, null, { code: 9999 }, loaded(fakeProj({ unknown: [9999] }))), /unknown EPSG code 9999/);
});

test("each definition is made once per proj.wasm instance", async () => {
  const proj = fakeProj();
  for (const crs of [slots(1), slots(1), slots(2)]) await toLonLat(table([[[1, 2]]]).bytes, null, crs, loaded(proj));
  assert.equal(proj.log.definitions.length, 2);
  assert.equal(proj.log.definitions[0][0], 1);
  assert.deepEqual(proj.log.transforms, [[-1, 4326], [-1, 4326], [-2, 4326]]);
  const again = fakeProj();
  await toLonLat(table([[[1, 2]]]).bytes, null, slots(1), loaded(again));
  assert.equal(again.log.definitions.length, 1);
});

test("transformPairs goes either way, NaN out of reach, and refuses unknown codes", () => {
  const proj = fakeProj({ reach: 100 });
  assert.deepEqual(Array.from(transformPairs(proj, 4326, 6677, Float64Array.of(1, 2, 3, 4))), [4327, 6679, 4329, 6681]);
  assert.deepEqual(Array.from(transformPairs(proj, 6677, 4326, Float64Array.of(200, 2))), [NaN, 4328]);
  assert.throws(() => transformPairs(fakeProj({ unknown: [9999] }), 9999, 4326, Float64Array.of(1, 2)), /unknown EPSG code 9999/);
});

test("transformPairs reads a view of a larger buffer", () => {
  const whole = Float64Array.of(9, 9, 1, 2, 9, 9);
  assert.deepEqual(Array.from(transformPairs(fakeProj(), 6677, 4326, whole.subarray(2, 4))), [6678, 4328]);
});

test("proj.wasm running out of memory is said so", () => {
  const proj = fakeProj();
  proj.transform_coords = () => -2;
  assert.throws(() => transformPairs(proj, 6677, 4326, Float64Array.of(1, 2)), /^Error: out of memory$/);
});
