import assert from "node:assert/strict";
import test from "node:test";
import { breakdown, defaultLabel } from "../src/ui/legend-rules.ts";
import { withOverlays } from "../src/ui/overlays.ts";

test("breakdown: a match on a property gives its labels and the fallback", () => {
  const b = breakdown(["match", ["get", "ftCode"], 3103, "#d9c9b6", [3101, 3102], "#ccc", "#e3ddd3"]);
  assert.equal(b.kind, "match");
  assert.equal(b.property, "ftCode");
  assert.deepEqual(b.categories, [
    { values: [3103], properties: { ftCode: 3103 } },
    { values: [3101, 3102], properties: { ftCode: 3101 } },
    { other: true, properties: {} },
  ]);
  assert.deepEqual(b.categories.map(defaultLabel), ["3103", "3101, 3102", "other"]);
});

test("breakdown: steps give ranges, interpolations their stops, a case of == its values", () => {
  const s = breakdown(["step", ["to-number", ["get", "n"]], "#000", 10, "#111", 20, "#222"]);
  assert.deepEqual(s.categories.map((c) => [c.range, c.properties.n]), [[[null, 10], 9], [[10, 20], 10], [[20, null], 20]]);
  assert.deepEqual(s.categories.map(defaultLabel), ["< 10", "10 – 20", "≥ 20"]);
  const i = breakdown(["interpolate", ["linear"], ["get", "h"], 0, "#fff", 100, "#000"]);
  assert.deepEqual(i.categories, [{ value: 0, properties: { h: 0 } }, { value: 100, properties: { h: 100 } }]);
  const c = breakdown(["case", ["==", ["get", "k"], "a"], "#f00", ["==", ["get", "k"], "b"], "#0f0", "#00f"]);
  assert.deepEqual(c.categories.map(defaultLabel), ["a", "b", "other"]);
});

test("breakdown: constants, zoom curves and mixed conditions are single entries", () => {
  for (const e of ["#fff", ["interpolate", ["linear"], ["zoom"], 5, "#fff", 10, "#000"], ["case", ["boolean", ["feature-state", "hover"], false], "#f00", "#00f"], ["match", ["geometry-type"], "Point", "#f00", "#00f"]]) {
    const b = breakdown(e);
    assert.equal(b.kind, "single");
    assert.deepEqual(b.categories, [{ properties: {} }]);
  }
});

test("withOverlays: keeps the overlays and their sources, in place or on top", () => {
  const overlay = { metadata: { "mbmap:overlay": true } };
  const previous = {
    sources: { base: { a: 1 }, pts: { data: "mine" } },
    layers: [{ id: "bg" }, { id: "pts", source: "pts", ...overlay }, { id: "pts-label", source: "pts", ...overlay }],
  };
  const next = { sources: { photo: {}, pts: { data: "theirs" } }, layers: [{ id: "photo", source: "photo" }, { id: "pts", source: "pts" }] };
  const out = withOverlays(previous, next);
  assert.deepEqual(out.layers.map((l) => l.id), ["photo", "pts", "pts-label"]);
  assert.deepEqual(out.sources, { photo: {}, pts: { data: "mine" } });
  assert.equal(withOverlays(undefined, next), next);
});
