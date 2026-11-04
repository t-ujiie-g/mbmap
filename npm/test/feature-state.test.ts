import assert from "node:assert/strict";
import test from "node:test";
import { removeStateError, stateIdError, stateLayer } from "../src/feature-state.ts";

test("stateLayer: the source layer of vector sources, empty elsewhere", () => {
  assert.equal(stateLayer({ type: "vector" }, { source: "v", sourceLayer: "road", id: 1 }), "road");
  assert.equal(stateLayer({ type: "geojson" }, { source: "g", sourceLayer: "ignored", id: 1 }), "");
});

test("stateLayer refuses a missing source and a vector source without sourceLayer", () => {
  const missing = stateLayer(undefined, { source: "nope" });
  assert.ok(missing instanceof Error);
  assert.match(missing.message, /the source 'nope' does not exist/);
  const noLayer = stateLayer({ type: "vector" }, { source: "v", id: 1 });
  assert.ok(noLayer instanceof Error);
  assert.match(noLayer.message, /sourceLayer parameter must be provided/);
});

test("stateIdError: an id is required and must not be empty", () => {
  assert.equal(stateIdError({ source: "g", id: 0 }), null);
  assert.equal(stateIdError({ source: "g", id: "a" }), null);
  for (const id of [undefined, ""]) {
    assert.match(stateIdError({ source: "g", id })?.message ?? "", /feature id parameter must be provided/);
  }
});

test("removeStateError: a key needs an id, a whole state does not", () => {
  assert.equal(removeStateError({ source: "g" }, undefined), null);
  assert.equal(removeStateError({ source: "g", id: 1 }, "hover"), null);
  assert.match(removeStateError({ source: "g" }, "hover")?.message ?? "", /feature id is required/);
});
