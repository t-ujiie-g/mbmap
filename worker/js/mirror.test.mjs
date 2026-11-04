import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { ICON_COLUMN, LINE_FLOATS, LINE_LEVELS } from "./symbols.mjs";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

// `const NAME : Int32 = 12` (pub or not) in a MoonBit file, literal values only.
function moonConsts(path) {
  const out = {};
  for (const [, name, value] of source(path).matchAll(/^(?:pub )?const ([A-Z0-9_]+) : Int32 = (-?\d+)$/gm)) out[name] = Number(value);
  return out;
}

// `const NAME = 12;` at the top level of a JS file.
function jsConsts(path) {
  const out = {};
  for (const [, name, value] of source(path).matchAll(/^const ([A-Z0-9_]+) = (-?\d+);/gm)) out[name] = Number(value);
  return out;
}

const packed = moonConsts("../packed.mbt");
const tiles = moonConsts("../../map/tiles.mbt");
const worker = jsConsts("./worker.mjs");

test("worker.mjs mirrors the packed tile's entry size and kinds", () => {
  assert.equal(worker.LAYER_ENTRY_WORDS, packed.LAYER_ENTRY_WORDS);
  assert.equal(worker.KIND_SYMBOL, packed.KIND_SYMBOL);
  assert.equal(worker.KIND_HILLSHADE, tiles.KIND_HILLSHADE);
  assert.equal(worker.KIND_RASTER, tiles.KIND_RASTER);
});

test("worker.mjs names an entry's words in worker/packed.mbt's ENTRY_* order", () => {
  const words = source("./worker.mjs").match(/const \[([^\]]*)\] =\s*Array\.from\(\{ length: LAYER_ENTRY_WORDS \}/);
  assert.ok(words, "the entry's words not found in worker.mjs");
  const js = words[1].split(",").map((name) => name.trim().replace(/[A-Z]/g, (c) => `_${c}`).toUpperCase());
  const moon = [];
  for (const [name, word] of Object.entries(packed)) if (name.startsWith("ENTRY_")) moon[word] = name.slice(6);
  assert.equal(moon.length, packed.LAYER_ENTRY_WORDS);
  assert.deepEqual(js, moon);
  assert.equal(js.indexOf("KIND"), 1, "hasSymbols reads word 1");
});

test("map's kinds are the worker's", () => {
  for (const kind of ["KIND_FILL", "KIND_LINE", "KIND_CIRCLE", "KIND_SYMBOL", "KIND_EXTRUSION"]) {
    const map = kind === "KIND_SYMBOL" ? moonConsts("../../map/labels.mbt") : tiles;
    assert.equal(map[kind], packed[kind], kind);
  }
});

test("symbols.mjs mirrors map's label columns and line levels", () => {
  const labels = moonConsts("../../map/labels.mbt");
  const lines = moonConsts("../../map/line_labels.mbt");
  assert.equal(ICON_COLUMN, labels.ICON_COLUMN);
  assert.equal(LINE_FLOATS, lines.LINE_FLOATS);
  assert.equal(LINE_LEVELS, lines.LINE_LEVELS);
});
