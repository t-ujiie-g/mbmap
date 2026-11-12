import assert from "node:assert/strict";
import test from "node:test";
import { loadSprites } from "../src/sprite.ts";

const base = new URL("https://example.com/styles/style.json");
const read = async (res: Response) => new Uint8Array(await res.arrayBuffer());

/** A PNG header of `width` x `height` (enough for the size check before decoding). */
function png(width: number, height: number): Uint8Array {
  const b = new Uint8Array(33);
  b.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]);
  new DataView(b.buffer).setUint32(16, width);
  new DataView(b.buffer).setUint32(20, height);
  return b;
}

/** A 2 x 1 sheet decoded without a browser: pixel x has red 10 + x. */
function fakeCanvas(): void {
  Object.assign(globalThis, {
    createImageBitmap: async () => ({ width: 2, height: 1, close() {} }),
    OffscreenCanvas: class {
      getContext() {
        return { drawImage() {}, getImageData: () => ({ data: new Uint8ClampedArray([10, 0, 0, 255, 11, 0, 0, 255]) }) };
      }
    },
  });
}

function server(files: Record<string, unknown>) {
  const asked: string[] = [];
  const fetch = async (url: string, type: string) => {
    asked.push(`${type} ${url}`);
    const body = files[url];
    if (body === undefined) return new Response(null, { status: 404 });
    return new Response(body instanceof Uint8Array ? body : JSON.stringify(body));
  };
  return { asked, fetch };
}

test("loadSprites asks for the @2x sheets above pixel ratio 1, relative to the style", async () => {
  fakeCanvas();
  const index = { a: { x: 1, y: 0, width: 1, height: 1, pixelRatio: 2 } };
  const { asked, fetch } = server({ "https://example.com/s@2x.json": index, "https://example.com/s@2x.png": png(2, 1) });
  const images = await loadSprites("../s", 2, base, fetch, read);
  assert.deepEqual(asked, ["SpriteJSON https://example.com/s@2x.json", "SpriteImage https://example.com/s@2x.png"]);
  assert.equal(images.length, 1);
  assert.equal(images[0].name, "a");
  assert.equal(images[0].pixelRatio, 2);
  assert.deepEqual([...images[0].pixels.data], [11, 0, 0, 255]);
});

test("loadSprites prefixes the images of named sprites but the default", async () => {
  fakeCanvas();
  const index = { a: { x: 0, y: 0, width: 1, height: 1 } };
  const { fetch } = server({ "https://t/x.json": index, "https://t/x.png": png(2, 1), "https://t/y.json": index, "https://t/y.png": png(2, 1) });
  const images = await loadSprites([{ id: "default", url: "https://t/x" }, { id: "more", url: "https://t/y" }], 1, base, fetch, read);
  assert.deepEqual(images.map((i) => i.name), ["a", "more:a"]);
});

test("loadSprites rejects a missing sheet, a sheet too large and a URL that is not http(s)", async () => {
  fakeCanvas();
  const { fetch } = server({ "https://t/s.json": {} });
  await assert.rejects(loadSprites("https://t/s", 1, base, fetch, read), /sprite https:\/\/t\/s: HTTP 404/);
  const big = server({ "https://t/s.json": {}, "https://t/s.png": png(9000, 1) });
  await assert.rejects(loadSprites("https://t/s", 1, base, big.fetch, read), /9000 x 1, over 8192/);
  await assert.rejects(loadSprites("file:///s", 1, base, fetch, read));
  await assert.rejects(loadSprites("https://t/s", 1, base, big.fetch, async (_, what) => { throw new Error(`${what}: too large`); }), /mbmap: sprite https:\/\/t\/s: too large/);
});

test("loadSprites loads nothing for a style without sprites", async () => {
  const { asked, fetch } = server({});
  assert.deepEqual(await loadSprites(null, 1, base, fetch, read), []);
  assert.deepEqual(asked, []);
});
