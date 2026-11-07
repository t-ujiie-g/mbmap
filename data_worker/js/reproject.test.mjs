import assert from "node:assert/strict";
import test from "node:test";
import { filled, isReprojected, MAX_SOURCE_TILES, matrixFor, reprojectTile, tilesOf } from "./reproject.mjs";

// The world in EPSG:4326 as 2 × 1 tiles of 256 pixels (0.703125° each), and twice as fine.
const world = (z) => ({ id: `m${z}`, resolution: 0.703125 / 2 ** z, x: -180, y: 90, width: 256, height: 256, cols: 2 * 2 ** z, rows: 2 ** z });
const grid = { crs: 4326, grid: { template: "https://a.test/{TileMatrix}/{TileRow}/{TileCol}.png", matrices: [world(0), world(1)] } };

// A source tile whose every pixel holds its matrix, row and column; `asked` records the URLs.
function context(asked, missing = () => false) {
  return {
    transform: async () => assert.fail("EPSG:4326 needs no transform"),
    image: async (url, max) => {
      asked.push(url);
      assert.deepEqual(max, [256, 256]);
      if (missing(url)) return null;
      const [, m, r, c] = /\/m(\d+)\/(\d+)\/(\d+)\.png$/.exec(url).map(Number);
      const data = new Uint8ClampedArray(256 * 256 * 4);
      for (let k = 0; k < data.length; k += 4) data.set([m, r, c, 255], k);
      return { width: 256, height: 256, data };
    },
    png: async (rgba) => rgba,
  };
}

test("isReprojected takes a grid or an image of an EPSG code, nothing else", () => {
  assert.ok(isReprojected(grid));
  assert.ok(isReprojected({ crs: 6677, image: { template: "https://a.test/?bbox={bbox}", northFirst: true } }));
  assert.ok(!isReprojected({ crs: 0, image: { template: "x", northFirst: true } }));
  assert.ok(!isReprojected({ crs: 4326 }));
  assert.ok(!isReprojected({ ...grid, image: { template: "x", northFirst: false } }));
  assert.ok(!isReprojected({ crs: 4326, grid: { template: "x", matrices: [{ ...world(0), width: 0 }] } }));
  assert.ok(!isReprojected({ crs: 4326, grid: { template: "x", matrices: [{ ...world(0), resolution: -1 }] } }));
  assert.ok(!isReprojected(null));
});

test("filled puts values in the template, encoded, its own keys only, and refuses other schemes", () => {
  assert.equal(filled("https://a.test/{constructor}", {}), "https://a.test/{constructor}");
  assert.equal(filled("https://a.test/{TileMatrix}/{a}?b={bbox}", { TileMatrix: "EPSG:4326:3", bbox: "1,2,3,4" }), "https://a.test/EPSG%3A4326%3A3/{a}?b=1,2,3,4");
  assert.throws(() => filled("{x}", { x: "javascript:alert(1)" }), /http\(s\)/);
});

test("matrixFor takes the coarsest matrix still finer than wanted, else the finest", () => {
  const ms = [world(0), world(1), world(2)];
  assert.equal(matrixFor(ms, 0.5).id, "m1");
  assert.equal(matrixFor(ms, 0.703125).id, "m0");
  assert.equal(matrixFor(ms, 0.01).id, "m2");
});

test("tilesOf finds the tiles a box meets, clamped to the matrix", () => {
  assert.deepEqual(tilesOf(world(1), [-10, -10, 10, 10]), [1, 0, 2, 1]);
  assert.deepEqual(tilesOf(world(1), [-400, -100, 400, 100]), [0, 0, 3, 1]);
  assert.equal(tilesOf(world(1), [200, 0, 210, 10]), null);
});

test("reprojectTile reads each pixel from the source tile under it", async () => {
  const asked = [];
  const rgba = await reprojectTile(grid, { z: 0, x: 0, y: 0, tileSize: 256 }, context(asked));
  // A z0 tile pixel is 1.40625° wide: matrix m0 (0.703125°) is the coarsest finer than that.
  assert.deepEqual(asked.toSorted(), ["https://a.test/m0/0/0.png", "https://a.test/m0/0/1.png"]);
  const at = (i, j) => [...rgba.subarray((j * 256 + i) * 4, (j * 256 + i) * 4 + 4)];
  assert.deepEqual(at(10, 128), [0, 0, 0, 255]);
  assert.deepEqual(at(250, 128), [0, 0, 1, 255]);
  const right = await reprojectTile(grid, { z: 3, x: 6, y: 3, tileSize: 256 }, context([]));
  assert.deepEqual([...right.subarray(0, 4)], [1, 0, 3, 255]);
});

test("reprojectTile gives null where no source tile is, and refuses too many tiles", async () => {
  assert.equal(await reprojectTile(grid, { z: 0, x: 0, y: 0 }, context([], () => true)), null);
  const many = { crs: 4326, grid: { template: grid.grid.template, matrices: [{ ...world(0), resolution: 0.0001, cols: 1e6, rows: 1e6 }] } };
  const asked = [];
  assert.equal(await reprojectTile(many, { z: 0, x: 0, y: 0 }, context(asked)), null);
  assert.ok(asked.length === 0 && MAX_SOURCE_TILES === 64);
});

test("reprojectTile asks one GetMap of the tile's box, north first when told, and reads it", async () => {
  const asked = [];
  const ctx = {
    transform: async () => assert.fail("no transform"),
    image: async (url, max) => {
      asked.push(url);
      const q = new URL(url).searchParams;
      const [w, h] = [Number(q.get("w")), Number(q.get("h"))];
      assert.deepEqual(max, [w, h]);
      const data = new Uint8ClampedArray(w * h * 4);
      for (let k = 0; k < data.length; k += 4) data.set([9, 8, 7, 255], k);
      return { width: w, height: h, data };
    },
    png: async (rgba) => rgba,
  };
  const spec = { crs: 4326, image: { template: "https://a.test/wms?bbox={bbox}&w={width}&h={height}", northFirst: true } };
  const rgba = await reprojectTile(spec, { z: 10, x: 909, y: 403 }, ctx);
  const q = new URL(asked[0]).searchParams;
  const [s, w, n, e] = q.get("bbox").split(",").map(Number);
  assert.ok(s < 35.7 && n > 35.6 && w < 139.6 && e > 139.5 && s < n && w < e);
  assert.ok(Number(q.get("w")) >= 256 && Number(q.get("w")) <= 270);
  assert.deepEqual([...rgba.subarray(0, 4)], [9, 8, 7, 255]);
});

test("reprojectTile takes pixels through the CRS's transform", async () => {
  const calls = [];
  const ctx = {
    // A plane whose coordinates are degrees times 1000.
    transform: async (from, to, xy) => (calls.push([from, to]), xy.map((v) => v * 1000)),
    image: async () => ({ width: 1, height: 1, data: new Uint8ClampedArray([1, 2, 3, 255]) }),
    png: async (rgba) => rgba,
  };
  const spec = { crs: 6677, grid: { template: "https://a.test/{TileMatrix}/{TileRow}/{TileCol}.png", matrices: [{ ...world(0), resolution: 1e6, x: -180000, y: 90000, width: 1, height: 1, cols: 1, rows: 1 }] } };
  const rgba = await reprojectTile(spec, { z: 0, x: 0, y: 0 }, ctx);
  assert.deepEqual(calls, [[4326, 6677]]);
  assert.deepEqual([...rgba.subarray(0, 4)], [1, 2, 3, 255]);
});
