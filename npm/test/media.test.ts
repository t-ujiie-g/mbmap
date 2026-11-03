import assert from "node:assert/strict";
import test from "node:test";
import { Media, type MediaEngine, mediaUrl, quadOf } from "../src/media.ts";

// Expected tiles, corners (MapLibre's 8192 units halved) and warps from MapLibre 6.16's ImageSource.
const close = (a: number[], b: number[]) => assert.ok(a.every((v, i) => Math.abs(v - b[i]) < 1e-12), `${a} vs ${b}`);

test("quadOf places a rectangle in its center tile, bilinear", () => {
  const q = quadOf([[139.76, 35.69], [139.78, 35.69], [139.78, 35.675], [139.76, 35.675]]);
  assert.deepEqual(q.slice(0, 15), [14, 14553, 6451, -1503.5, 687.5, 2224.5, 687.5, 2224.5, 4130, -1503.5, 4130, 0, 0, 1, 0]);
  assert.equal(q.length, 19);
});

test("quadOf gives a mild trapezoid a projective warp, a strong one a blended warp over a grid", () => {
  const mild = quadOf([[139.755, 35.692], [139.785, 35.688], [139.79, 35.668], [139.75, 35.672]]);
  assert.deepEqual(mild.slice(0, 11), [13, 7276, 3225, 830, 2162, 3626.5, 2621, 4092.5, 4916, 364, 4457]);
  close(mild.slice(11, 15), [0.05127499793689654, -0.2563749896844827, 0, 0]);
  const strong = quadOf([[139.768, 35.69], [139.772, 35.69], [139.79, 35.67], [139.75, 35.67]]);
  close(strong.slice(11, 15), [0, -0.9000938715301059, 0.6051028521528679, 1]);
});

test("quadOf gives a concave quad the bilinear warp over a grid and refuses malformed corners", () => {
  assert.deepEqual(quadOf([[139.7, 35.7], [139.8, 35.7], [139.71, 35.69], [139.7, 35.6]]).slice(0, 3), [11, 1819, 806]);
  assert.deepEqual(quadOf([[139.7, 35.7], [139.8, 35.7], [139.71, 35.69], [139.7, 35.6]]).slice(11, 15), [0, 0, 1, 1]);
  for (const bad of [undefined, [[1, 2], [3, 4], [5, 6]], [[1, 2], [3, 4], [5, 6], [7, "8"]], [[1, 2], [3, 4], [5, 6], [7]], Array(4).fill([10, 10])]) {
    assert.deepEqual(quadOf(bad), []);
  }
});

test("mediaUrl resolves against the style and refuses other schemes than http(s)", () => {
  const base = new URL("https://example.com/styles/style.json");
  assert.equal(mediaUrl("../img/a.png", base), "https://example.com/img/a.png");
  assert.throws(() => mediaUrl("data:image/png;base64,AA", base), /http\(s\)/);
  assert.throws(() => mediaUrl("javascript:alert(1)", base), /http\(s\)/);
});

test("Media follows the style: shows, moves and keeps what did not change", () => {
  const calls: unknown[][] = [];
  const engine: MediaEngine = {
    show: (id, picture, quad) => calls.push(["show", id, picture, quad.length]),
    move: (id, quad) => calls.push(["move", id, quad[0]]),
    playing: (id, on) => calls.push(["playing", id, on]),
  };
  const errors: string[] = [];
  const media = new Media(engine, () => Promise.reject(new Error("no fetch")), (e) => errors.push(e.message));
  const base = new URL("https://example.com/");
  const corners = [[139.76, 35.69], [139.78, 35.69], [139.78, 35.675], [139.76, 35.675]];
  media.set([{ id: "a", spec: { type: "image", coordinates: corners } }], base);
  assert.deepEqual(calls, [["show", "a", null, 19]]);
  media.set([{ id: "a", spec: { type: "image", coordinates: corners } }], base);
  assert.equal(calls.length, 1);
  media.set([{ id: "a", spec: { type: "image", coordinates: corners.map(([x, y]) => [x * 1.0001, y]) } }], base);
  assert.deepEqual(calls[1], ["move", "a", 14]);
  media.set([{ id: "a", spec: { type: "image", coordinates: [[0, 0]] } }], base);
  assert.deepEqual(calls[2], ["move", "a", undefined]);
  assert.match(errors[0], /coordinates must be four/);
  media.set([{ id: "b", spec: { type: "image", url: "file:///etc/passwd", coordinates: corners } }], base);
  assert.deepEqual(calls[3], ["show", "b", null, 19]);
  assert.match(errors[1], /http\(s\)/);
});
