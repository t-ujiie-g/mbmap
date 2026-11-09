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
const kinds = moonConsts("../../core/kinds.mbt");
const worker = jsConsts("./worker.mjs");

test("worker.mjs mirrors the packed tile's entry size and kinds", () => {
  assert.equal(worker.LAYER_ENTRY_WORDS, packed.LAYER_ENTRY_WORDS);
  assert.equal(worker.KIND_SYMBOL, kinds.KIND_SYMBOL);
  assert.equal(worker.KIND_HILLSHADE, kinds.KIND_HILLSHADE);
  assert.equal(worker.KIND_RASTER, kinds.KIND_RASTER);
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

test("symbols.mjs and media.ts mirror core's tile extent", () => {
  const { TILE_EXTENT } = moonConsts("../../core/transform.mbt");
  assert.equal(jsConsts("./symbols.mjs").TILE_EXTENT, TILE_EXTENT);
  assert.equal(jsConsts("../../npm/src/media.ts").TILE_EXTENT, TILE_EXTENT);
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

test("custom.ts and the 3D model program mirror the custom layers' numbers and the shadow map's size", () => {
  const custom = moonConsts("../../map/custom.mbt");
  const ts = jsConsts("../../npm/src/custom.ts");
  for (const name of ["CUSTOM_TRANSITION", "CUSTOM_PLANE", "CUSTOM_LIGHTS", "CUSTOM_SHADOWS"]) assert.equal(ts[name], custom[name], name);
  // The shadows: mode, intensity, ground, texel, then two matrices.
  assert.equal(custom.CUSTOM_NUMBERS, custom.CUSTOM_SHADOWS + 4 + 32);
  assert.equal(jsConsts("../../npm/src/model/draw.ts").SHADOW_SIZE, moonConsts("../../core/shadow.mbt").SHADOW_MAP_SIZE);
});

// The constructors listed by `let name : FixedArray[...] = [A, B, ...]` in a MoonBit file, in order.
function moonList(path, name) {
  const list = source(path).match(new RegExp(`^let ${name} : FixedArray\\[[^\\]]+\\] = \\[([^\\]]*)\\]`, "m"));
  assert.ok(list, `${name} not found in ${path}`);
  return list[1].split(",").map((s) => s.trim()).filter(Boolean);
}

// The `{ KEY: number, ... }` or `{ key: [number, ...], ... }` object literal of `const NAME` in a JS file.
function jsTable(path, name) {
  const table = source(path).match(new RegExp(`^const ${name} = \\{([^}]*)\\};`, "m"));
  assert.ok(table, `${name} not found in ${path}`);
  return Object.fromEntries([...table[1].matchAll(/(\w+): \[?(\d+)/g)].map(([, key, n]) => [key, Number(n)]));
}

test("model_worker's decode.mjs numbers meshopt's modes and filters and LEPCC's kinds as the wasm does", () => {
  const upper = (name) => (name === "NoFilter" ? "NONE" : name.toUpperCase());
  const index = (list, key) => Object.fromEntries(list.map((name, i) => [key(name), i]));
  const decode = "../../model_worker/js/decode.mjs";
  assert.deepEqual(jsTable(decode, "MODES"), index(moonList("../../model_worker/model.mbt", "modes"), upper));
  assert.deepEqual(jsTable(decode, "FILTERS"), index(moonList("../../model_worker/model.mbt", "filters"), upper));
  assert.deepEqual(jsTable(decode, "LEPCC_KINDS"), index(moonList("../../model_worker/lepcc.mbt", "lepcc_kinds"), (name) => name.toLowerCase()));
});

test("model_worker's decode.mjs reads Draco's data types by draco/decode.mbt's DT_* numbers", () => {
  const types = moonConsts("../../draco/decode.mbt");
  const js = source("../../model_worker/js/decode.mjs").match(/^const DRACO_TYPES = \{([^\n]*)\};/m);
  assert.ok(js, "DRACO_TYPES not found");
  const pairs = [...js[1].matchAll(/(\d+): \[(\w+)Array/g)];
  assert.ok(pairs.length > 0);
  for (const [, n, typed] of pairs) assert.equal(Number(n), types[`DT_${typed.toUpperCase()}`], typed);
});
