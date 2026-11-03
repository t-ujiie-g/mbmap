import assert from "node:assert/strict";
import test from "node:test";
import { imageOptions, imagePixels, spriteImages, spriteList } from "../src/images.ts";

const noCanvas = () => {
  throw new Error("no canvas in this test");
};

test("imagePixels takes raw RGBA of the right size and refuses others", () => {
  const data = new Uint8ClampedArray(2 * 3 * 4).fill(9);
  const p = imagePixels({ width: 2, height: 3, data }, noCanvas);
  assert.equal(p.width, 2);
  assert.ok(p.data instanceof Uint8Array);
  assert.equal(p.data[5], 9);
  assert.throws(() => imagePixels({ width: 2, height: 2, data }, noCanvas), /width \* height \* 4/);
  assert.throws(() => imagePixels({ width: 0, height: 0, data: new Uint8Array(0) }, noCanvas));
});

test("imageOptions checks the pixel ratio", () => {
  assert.deepEqual(imageOptions(), { pixelRatio: 1, sdf: false });
  assert.deepEqual(imageOptions({ pixelRatio: 2, sdf: true }), { pixelRatio: 2, sdf: true });
  assert.throws(() => imageOptions({ pixelRatio: 0 }));
  assert.throws(() => imageOptions({ pixelRatio: Infinity }));
});

test("spriteImages cuts each entry out of the sheet, prefixed, and skips those outside", () => {
  // A 4 x 2 sheet whose pixel (x, y) has red x and green y.
  const sheet = { width: 4, height: 2, data: new Uint8Array(4 * 2 * 4) };
  for (let y = 0; y < 2; y++) for (let x = 0; x < 4; x++) sheet.data.set([x, y, 0, 255], (y * 4 + x) * 4);
  const images = spriteImages(
    {
      dot: { x: 1, y: 0, width: 2, height: 2, pixelRatio: 2, sdf: true },
      off: { x: 3, y: 1, width: 2, height: 2 },
      bad: { x: "a" },
    },
    sheet,
    "extra:",
  );
  assert.deepEqual(images.map((i) => i.name), ["extra:dot"]);
  const [dot] = images;
  assert.equal(dot.pixelRatio, 2);
  assert.equal(dot.sdf, true);
  assert.deepEqual([...dot.pixels.data.subarray(0, 8)], [1, 0, 0, 255, 2, 0, 0, 255]);
  assert.deepEqual([...dot.pixels.data.subarray(8, 12)], [1, 1, 0, 255]);
  assert.throws(() => spriteImages(null, sheet, ""));
});

test("spriteList reads one URL or a list of ids and URLs", () => {
  assert.deepEqual(spriteList("https://x/sprite"), [{ id: "default", url: "https://x/sprite" }]);
  assert.deepEqual(spriteList([{ id: "a", url: "u" }, { id: 1 }]), [{ id: "a", url: "u" }]);
  assert.deepEqual(spriteList(undefined), []);
});
