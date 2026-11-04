import assert from "node:assert/strict";
import test from "node:test";
import { CLICK_TOLERANCE, Events } from "../src/events.ts";
import type { Map } from "../src/index.ts";
import type { MapEvent } from "../src/types.ts";

const target = { unproject: (p: { x: number; y: number }) => ({ lng: p.x, lat: p.y }), getLayer: () => undefined } as unknown as Map;
const mouse = {} as MouseEvent;

test("a click fires only after less than CLICK_TOLERANCE px of movement since the press", () => {
  const events = new Events(target, () => Promise.resolve([]));
  const clicks: MapEvent[] = [];
  events.on("click", (e) => clicks.push(e));
  events.mouse("mousedown", mouse, { x: 10, y: 10 });
  events.mouse("click", mouse, { x: 10 + CLICK_TOLERANCE - 0.5, y: 10 });
  events.mouse("mousedown", mouse, { x: 10, y: 10 });
  events.mouse("click", mouse, { x: 10, y: 10 + CLICK_TOLERANCE });
  assert.equal(CLICK_TOLERANCE, 3);
  assert.equal(clicks.length, 1);
  assert.deepEqual(clicks[0].point, { x: 12.5, y: 10 });
  assert.deepEqual(clicks[0].lngLat, { lng: 12.5, lat: 10 });
});

test("once without a listener returns a Promise of the next event, then stops listening", async () => {
  const events = new Events(target, () => Promise.resolve([]));
  const next = events.once("idle");
  assert.ok(next instanceof Promise);
  events.emit("idle");
  const e = await next;
  assert.equal(e.type, "idle");
  assert.equal(e.target, target);
  assert.equal(events.has("idle"), false);
});

test("once with a listener calls it for one event only", () => {
  const events = new Events(target, () => Promise.resolve([]));
  let n = 0;
  assert.equal(events.once("render", () => n++), undefined);
  events.emit("render");
  events.emit("render");
  assert.equal(n, 1);
});

test("layer listeners get the features a query finds; clear drops every listener", async () => {
  const feature = { type: "Feature", geometry: null, properties: {}, layer: { id: "a" } };
  const events = new Events(target, (_, layers) => Promise.resolve(layers.includes("a") ? [feature as never] : []));
  const got: MapEvent[] = [];
  events.on("click", "a", (e) => got.push(e));
  (target as unknown as { getLayer: (id: string) => unknown }).getLayer = (id) => (id === "a" ? {} : undefined);
  events.mouse("click", mouse, { x: 1, y: 2 });
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(got.length, 1);
  assert.deepEqual(got[0].features, [feature]);
  events.clear();
  events.mouse("click", mouse, { x: 1, y: 2 });
  await new Promise((r) => setTimeout(r, 0));
  assert.equal(got.length, 1);
});
