import assert from "node:assert/strict";
import test from "node:test";
import { convertFilter, convertFunction, convertStyle, convertTokenString, isLegacyFilter as legacyIsLegacy } from "../src/legacy.ts";
import { hasLegacy, isLegacyFilter } from "../src/style.ts";
import type { StyleSpecification } from "../src/style.ts";

test("legacy filters become expressions as MapLibre converts them", () => {
  assert.deepEqual(convertFilter(["==", "class", "x"]), ["==", ["get", "class"], "x"]);
  assert.deepEqual(convertFilter(["==", "$type", "Point"]), ["==", ["geometry-type"], "Point"]);
  assert.deepEqual(convertFilter(["==", "k", null]), ["all", ["has", "k"], ["==", ["get", "k"], null]]);
  assert.deepEqual(convertFilter(["in", "class", "b", "a", "b"]), ["match", ["get", "class"], ["a", "b"], true, false]);
  assert.deepEqual(convertFilter(["!in", "k", 1, "1"]), ["all", ["!=", ["get", "k"], 1], ["!=", ["get", "k"], "1"]]);
  assert.deepEqual(convertFilter(["has", "$id"]), ["!=", ["id"], null]);
  assert.deepEqual(convertFilter(["!has", "k"]), ["!", ["has", "k"]]);
  assert.deepEqual(convertFilter(["any", [">", "a", 1], ["has", "b"]]), [
    "any",
    ["case", ["==", ["typeof", ["get", "a"]], "number"], [">", ["get", "a"], 1], false],
    ["has", "b"],
  ]);
  assert.deepEqual(convertFilter(["none", ["==", "a", 1]]), ["!", ["any", ["case", ["==", ["typeof", ["get", "a"]], "number"], ["==", ["get", "a"], 1], false]]]);
  assert.deepEqual(convertFilter(["all", ["==", "a", 1]]), ["==", ["get", "a"], 1]);
  assert.deepEqual(convertFilter(["any"]), ["any"]);
  assert.equal(convertFilter(["none"]), true);
  const expression = ["==", ["get", "a"], 1];
  assert.equal(convertFilter(expression), expression);
});

test("legacy functions become expressions, by the property's type", () => {
  assert.deepEqual(convertFunction({ stops: [[12, 1], [18, 10]] }, "line-width"), ["interpolate", ["linear"], ["zoom"], 12, 1, 18, 10]);
  assert.deepEqual(convertFunction({ stops: [[12, "round"]] }, "line-cap"), ["step", ["zoom"], "round", 0, "round"]);
  assert.deepEqual(convertFunction({ property: "k", type: "categorical", stops: [["a", "#f00"]], default: "#000" }, "fill-color"), [
    "match",
    ["get", "k"],
    "a",
    "#f00",
    "#000",
  ]);
  assert.deepEqual(convertFunction({ property: "k", type: "identity" }, "fill-color"), ["get", "k"]);
  assert.deepEqual(convertFunction({ property: "k", type: "identity", default: 2 }, "line-width"), ["number", ["get", "k"], 2]);
  assert.deepEqual(convertFunction({ property: "k", stops: [[0, 1], [10, 5]], default: 3 }, "circle-radius"), [
    "case",
    ["==", ["typeof", ["get", "k"]], "number"],
    ["interpolate", ["linear"], ["number", ["get", "k"]], 0, 1, 10, 5],
    3,
  ]);
  assert.deepEqual(convertFunction({ stops: [[{ zoom: 10, value: 0 }, 1], [{ zoom: 18, value: 0 }, 4]], property: "k" }, "line-width"), [
    "interpolate",
    ["linear"],
    ["zoom"],
    10,
    ["interpolate", ["linear"], ["number", ["get", "k"]], 0, 1],
    18,
    ["interpolate", ["linear"], ["number", ["get", "k"]], 0, 4],
  ]);
  assert.equal(convertFunction({ stops: [[0, 1]] }, "no-such-property"), undefined);
  assert.throws(() => convertFunction({ property: "k", type: "spline", stops: [[0, 1]] }, "line-width"));
});

test("token strings become concat", () => {
  assert.deepEqual(convertTokenString("{name} ({ref})"), ["concat", ["get", "name"], " (", ["get", "ref"], ")"]);
  assert.deepEqual(convertTokenString("{name}"), ["to-string", ["get", "name"]]);
  assert.equal(convertTokenString("plain"), "plain");
});

test("convertStyle converts filters and functions and keeps the input", () => {
  const style = {
    version: 8,
    sources: {},
    layers: [
      { id: "a", type: "line", filter: ["==", "k", 1], paint: { "line-width": { stops: [[0, 1]] }, "line-width-transition": { duration: 0 } } },
      { id: "b", type: "background" },
    ],
  };
  const before = JSON.stringify(style);
  const out = convertStyle(style);
  assert.equal(JSON.stringify(style), before);
  assert.deepEqual(out.layers[0], {
    id: "a",
    type: "line",
    filter: ["==", ["get", "k"], 1],
    paint: { "line-width": ["interpolate", ["linear"], ["zoom"], 0, 1], "line-width-transition": { duration: 0 } },
  });
  assert.deepEqual(out.layers[1], { id: "b", type: "background" });
});

test("hasLegacy and isLegacyFilter tell styles that need the converter", () => {
  const style = (layer: object): StyleSpecification => ({ version: 8, sources: {}, layers: [{ id: "a", type: "fill", ...layer }] });
  assert.equal(hasLegacy(style({ filter: ["==", ["get", "k"], 1] })), false);
  assert.equal(hasLegacy(style({ filter: ["==", "k", 1] })), true);
  assert.equal(hasLegacy(style({ paint: { "fill-color": { stops: [[0, "#000"]] } } })), true);
  assert.equal(hasLegacy(style({ paint: { "fill-color": ["get", "c"] }, layout: { visibility: "visible" } })), false);
  for (const f of [["in", "k", "a"], ["!in", "k"], ["!has", "k"], ["has", "$type"], ["none"], ["all", ["==", "k", 1]], null]) {
    assert.equal(isLegacyFilter(f), true, JSON.stringify(f));
  }
  for (const f of [true, undefined, ["has", "k"], ["in", ["get", "k"], ["literal", []]], ["in", "a", ["get", "s"]], ["all", ["has", "k"]], ["get", "b"]]) {
    assert.equal(isLegacyFilter(f), false, JSON.stringify(f));
  }
});

test("filters nested past the engine's depth are left to it, without deep recursion", () => {
  let deep: unknown = ["==", "k", 1];
  for (let i = 0; i < 100000; i++) deep = ["all", deep];
  assert.equal(isLegacyFilter(deep), false);
  assert.equal(legacyIsLegacy(deep), false);
  assert.equal(convertFilter(deep as never), deep);
});

test("property names like Object.prototype's keys pass through convertStyle untouched", () => {
  const style = JSON.parse(
    '{"version": 8, "sources": {}, "layers": [{"id": "a", "type": "line", "paint": {"constructor": {"stops": [[0, 1]]}, "__proto__": {"stops": [[0, 2]]}, "line-width": {"stops": [[0, 3]]}}}]}',
  ) as StyleSpecification;
  const paint = (convertStyle(style).layers[0] as { paint: Record<string, unknown> }).paint;
  assert.deepEqual(Object.keys(paint).sort(), ["__proto__", "constructor", "line-width"]);
  assert.equal(Object.getPrototypeOf(paint), Object.prototype);
  assert.deepEqual(convertFilter(["==", "__proto__", 1]), ["==", ["get", "__proto__"], 1]);
  assert.deepEqual(convertFilter(["any", ["<", "constructor", 1]]), ["any", ["case", ["==", ["typeof", ["get", "constructor"]], "number"], ["<", ["get", "constructor"], 1], false]]);
});
