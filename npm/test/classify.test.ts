import assert from "node:assert/strict";
import test from "node:test";
import { classBreaks, classStep, MAX_CKMEANS_CELLS, MAX_CLASS_VALUES, MAX_CLASSES, MAX_JENKS_WORK, statistics } from "../src/classify.ts";

const values = [1, 2, 4, 5, 7, 9, 10, 20, 21, 22, null, Number.NaN, "3"];

test("statistics summarise the finite numbers only", () => {
  // simple-statistics' values for the same numbers.
  assert.deepEqual(statistics(values), { count: 10, min: 1, max: 22, sum: 101, mean: 10.1, median: 8, variance: 58.089999999999996, standardDeviation: 7.6216796049164905 });
  assert.equal(statistics([null, "x"]), null);
  assert.equal(statistics([4])!.standardDeviation, 0);
});

test("classBreaks divides by each method, lowest bound first", () => {
  assert.deepEqual(classBreaks(values, 3, "jenks"), [1, 7, 20, 22]);
  assert.deepEqual(classBreaks(values, 3, "ckmeans"), [1, 7, 20, 22]);
  assert.deepEqual(classBreaks(values, 2, "quantile"), [1, 8, 22]);
  assert.deepEqual(classBreaks(values, 3, "equalInterval"), [1, 8, 15, 22]);
  assert.deepEqual(classBreaks(values, 2, "standardDeviation"), [2.478320395083509, 10.1, 17.72167960491649]);
  assert.deepEqual(classBreaks(values, 2, "standardDeviation", { matchBounds: true }), [1, 10.1, 22]);
});

test("classBreaks gives null where simple-statistics gives none or throws", () => {
  assert.equal(classBreaks([], 3), null);
  assert.equal(classBreaks([1, 2], 3, "jenks"), null);
  assert.equal(classBreaks([1, 2], 3, "ckmeans"), null);
  assert.equal(classBreaks([5, 5, 5, 5], 3, "jenks"), null);
  assert.deepEqual(classBreaks([5, 5, 5, 5], 3, "ckmeans"), [5, 5]);
});

test("classBreaks refuses bad class counts, methods and too many values", () => {
  assert.throws(() => classBreaks(values, 0), /classes must be an integer/);
  assert.throws(() => classBreaks(values, MAX_CLASSES + 1), /classes must be an integer/);
  assert.throws(() => classBreaks(values, 2.5), /classes must be an integer/);
  assert.throws(() => classBreaks(values, 2, "nope" as never), /unknown method/);
  assert.throws(() => statistics({ length: MAX_CLASS_VALUES + 1 }), /more than/);
});

test("classStep makes a step expression with one output per class", () => {
  assert.deepEqual(classStep(["get", "v"], [1, 7, 20, 22], ["#a", "#b", "#c"]), ["step", ["get", "v"], "#a", 7, "#b", 20, "#c"]);
  assert.throws(() => classStep(["get", "v"], [1, 7, 20, 22], ["#a"]), /one output per class/);
});

test("classStep keeps the later output of equal breaks and refuses breaks out of order", () => {
  assert.deepEqual(classStep(["get", "v"], [1, 7, 7, 22], ["#a", "#b", "#c"]), ["step", ["get", "v"], "#a", 7, "#c"]);
  assert.deepEqual(classStep(["get", "v"], [1, 1, 7, 7, 7], ["#a", "#b", "#c", "#d"]), ["step", ["get", "v"], "#a", 1, "#b", 7, "#d"]);
  assert.throws(() => classStep(["get", "v"], [1, 7, 3, 22], ["#a", "#b", "#c"]), /breaks must ascend/);
  assert.throws(() => classStep(["get", "v"], [1, NaN, 22], ["#a", "#b"]), /breaks must ascend/);
});

test("classBreaks refuses jenks and ckmeans past their work caps", () => {
  const ramp = (n: number) => Array.from({ length: n }, (_, i) => i);
  const k = 10;
  const n = Math.floor(Math.sqrt(MAX_JENKS_WORK / k));
  assert.ok(n * n * k <= MAX_JENKS_WORK && (n + 1) * (n + 1) * k > MAX_JENKS_WORK);
  assert.throws(() => classBreaks(ramp(n + 1), k, "jenks"), /too many for jenks/);
  assert.equal(classBreaks(ramp(2000), k, "jenks")!.length, k + 1);
  const m = MAX_CKMEANS_CELLS / 100;
  assert.throws(() => classBreaks(ramp(m + 1), 100, "ckmeans"), /too many for ckmeans/);
  assert.equal(classBreaks(ramp(m), 2, "ckmeans")!.length, 3);
  assert.equal(classBreaks(ramp(m + 1), 100, "quantile")!.length, 101);
});
