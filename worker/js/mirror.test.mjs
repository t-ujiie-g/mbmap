import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { ICON_COLUMN, LINE_FLOATS, LINE_LEVELS } from "./symbols.mjs";

const source = (path) => readFileSync(new URL(path, import.meta.url), "utf8");

const product = (text) => text.split(" * ").reduce((n, factor) => n * Number(factor), 1);

// `const NAME : Int32 = 12` (pub or not) in a MoonBit file: a literal, a product of literals, or `OTHER + 1`.
function moonConsts(path) {
  const out = {};
  for (const [, name, value, base, add] of source(path).matchAll(/^(?:pub )?const ([A-Z0-9_]+) : Int32 = (?:(-?\d+(?: \* \d+)*)|([A-Z0-9_]+) \+ (\d+))$/gm)) {
    out[name] = value === undefined ? out[base] + Number(add) : product(value);
  }
  return out;
}

// `const NAME = 12;` (exported or not) at the top level of a JS or TS file: a literal or a product of literals.
function jsConsts(path) {
  const out = {};
  for (const [, name, value] of source(path).matchAll(/^(?:export )?const ([A-Z0-9_]+) = (-?\d+(?: \* \d+)*);/gm)) out[name] = product(value);
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

test("symbols.mjs mirrors map's label row and quad sizes", () => {
  const symbols = jsConsts("./symbols.mjs");
  assert.equal(symbols.LABEL_FLOATS, moonConsts("../../map/labels.mbt").LABEL_FLOATS);
  assert.equal(symbols.QUAD_INDICES, moonConsts("../../map/label_boxes.mbt").QUAD_INDICES);
});

test("CRS definitions have proj/encoding.mbt's slots everywhere", () => {
  const { DEFINITION_SLOTS } = moonConsts("../../proj/encoding.mbt");
  assert.equal(jsConsts("../../npm/src/prjwkt.ts").SLOTS, DEFINITION_SLOTS);
  assert.equal(jsConsts("../../npm/src/projstring.ts").SLOTS, DEFINITION_SLOTS);
  assert.equal(jsConsts("../../analysis_worker/js/worker.mjs").DEFINITION_SLOTS, DEFINITION_SLOTS);
  assert.equal(jsConsts("../../data_worker/js/read.mjs").DEFINITION_SLOTS, DEFINITION_SLOTS);
});

test("input limits match the wasm's", () => {
  assert.equal(jsConsts("../../wasmio/js/host.mjs").MAX_INPUT_BYTES, moonConsts("../../wasmio/memory.mbt").MAX_INPUT_BYTES);
  assert.equal(jsConsts("./body.mjs").MAX_BODY_BYTES, packed.MAX_PACKED_BYTES);
});

test("the DEM grid's limit is analysis_worker/dem.mbt's", () => {
  const { MAX_GRID_SIDE } = moonConsts("../../analysis_worker/dem.mbt");
  assert.equal(jsConsts("../../analysis_worker/js/worker.mjs").MAX_GRID_SIDE, MAX_GRID_SIDE);
  assert.equal(jsConsts("../../npm/src/dem-zoom.ts").MAX_GRID_SIDE, MAX_GRID_SIDE);
});

test("mbmap/analysis names measures as analysis_worker/datasets.mbt numbers them", () => {
  const moon = moonConsts("../../analysis_worker/datasets.mbt");
  const line = source("../../npm/src/analysis.ts").match(/^const MEASURE = \{([^}]*)\} as const;$/m);
  assert.ok(line, "MEASURE not found in npm/src/analysis.ts");
  const entries = line[1].split(",").map((entry) => entry.split(":").map((part) => part.trim()));
  assert.equal(entries.length, Object.keys(moon).filter((name) => name.startsWith("MEASURE_")).length);
  for (const [name, value] of entries) assert.equal(Number(value), moon[`MEASURE_${name.toUpperCase()}`], name);
});

test("values.mjs reads core's value tags", () => {
  const core = moonConsts("../../core/bytes.mbt");
  const js = Object.entries(jsConsts("./values.mjs"));
  assert.equal(js.length, 5);
  for (const [name, tag] of js) assert.equal(tag, core[name], name);
});
