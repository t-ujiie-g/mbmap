// Expressions (expression-cases.mjs) on GSI features by style-spec 26.5.0 (maplibre-gl 6.16.0's) and by
// bench/expr's js build must agree; legacy filters and functions convert as its convertFilter/convertFunction.
// Usage: node style/expressions.mjs; writes bench/results/expression-golden.json.
import { readdirSync, readFileSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { VectorTile } from "@mapbox/vector-tile";
import { convertFilter, convertFunction, createExpression, featureFilter, latest, normalizePropertyExpression } from "@maplibre/maplibre-gl-style-spec";
import { PbfReader } from "pbf";
import * as legacy from "../../npm/src/legacy.ts";
import { ROOT } from "../lib/root.mjs";
import { CASES, CONVERTED_OTHERWISE, LEGACY_FILTERS, LEGACY_FUNCTIONS, MAPLIBRE_REJECTS } from "./expression-cases.mjs";

const { expr_eval } = await import(pathToFileURL(path.join(ROOT, "_build/js/release/build/bench/expr/expr.js")).href);
const ZOOMS = [0, 9.5, 14, 17.25, 22];

function features() {
  const out = [];
  const dir = path.join(ROOT, "bench/fixtures/gsi-bvmap/14");
  const want = { label: 1e9, symbol: 1e9, contour: 1e9, railway: 1e9, elevation: 1e9, transp: 1e9, road: 150, building: 150, boundary: 30, waterarea: 20 };
  for (const x of readdirSync(dir).sort().slice(0, 2)) {
    for (const y of readdirSync(path.join(dir, x)).sort().slice(0, 2)) {
      const tile = new VectorTile(new PbfReader(readFileSync(path.join(dir, x, y))));
      const canonical = { z: 14, x: Number(x), y: Number(path.basename(y, ".pbf")) };
      for (const [name, max] of Object.entries(want)) {
        const layer = tile.layers[name];
        for (let i = 0; layer && i < Math.min(layer.length, max); i++) {
          const f = layer.feature(i);
          // As MapLibre's loadGeometry gives it (within, distance).
          const scale = 8192 / f.extent;
          const geometry = f.loadGeometry().map((ring) => ring.map((p) => ({ x: Math.round(p.x * scale), y: Math.round(p.y * scale) })));
          out.push({ type: f.type, properties: { ...f.properties }, geometry, canonical });
        }
      }
    }
  }
  // Ids for some, and properties of every kind for edge cases.
  out.forEach((f, i) => {
    if (i % 3 === 0) f.id = i;
  });
  const odd = [
    {},
    { n: NaN },
    { n: -0, s: "" },
    { n: Infinity, s: " 12 " },
    { n: -2.5, s: "0x1F" },
    { n: 0.5, s: "1e3", b: true },
    { n: 255, s: "#ff8000", b: false },
    { n: 1e21, s: "rgba(10, 20, 30, 0.5)" },
    { n: 3, s: "Tōkyō ÀÉ ß ｚ 𠮷", z: null },
    { n: 360, s: "abc", ftCode: "3103" },
    { s: "null", knj: "東京" },
    { s: "İı ĸ ŉ Ÿÿ ſ Ąą Łł Žž Привет ЁЖ ёж µ", kana: "ＡＢＣａｂｃ" },
  ];
  for (const props of odd) out.push({ type: 1, properties: props, id: "x" });
  out.push({ type: 2, properties: { n: 1 }, id: 7 }, { type: 3, properties: { n: 2 } });
  return out;
}

const SPEC = (type) => (type === "value" ? undefined : { type, "property-type": "data-driven", expression: { interpolated: true, parameters: ["zoom", "feature"] } });

/** A result in one shape for both engines: colors as straight RGBA, errors as `{ error }`. */
function maplibreValue(v) {
  if (v && typeof v === "object" && "r" in v && "rgb" in v) return { color: v.rgb };
  if (v && typeof v === "object" && Array.isArray(v.sections)) {
    return { formatted: v.sections.map((s) => [s.text, s.scale, s.fontStack, s.textColor ? { color: s.textColor.rgb } : null, s.verticalAlign]) };
  }
  if (v && typeof v === "object" && typeof v.sensitivity === "string") {
    return { collator: [v.sensitivity === "variant" || v.sensitivity === "case", v.sensitivity === "variant" || v.sensitivity === "accent", v.locale] };
  }
  if (Array.isArray(v)) return v.map(maplibreValue);
  return v === undefined ? null : v;
}

function same(a, b) {
  if (typeof a === "number" && typeof b === "number") return Object.is(a, b) || (Number.isNaN(a) && Number.isNaN(b));
  if (Array.isArray(a) && Array.isArray(b)) return a.length === b.length && a.every((x, i) => same(x, b[i]));
  if (a && b && typeof a === "object" && typeof b === "object") {
    if ("error" in a || "error" in b) return "error" in a && "error" in b;
    if ("color" in a && "color" in b) return a.color.every((x, i) => Math.abs(x - b.color[i]) <= 1e-9);
    for (const k of ["formatted", "collator"]) if (k in a && k in b) return same(a[k], b[k]);
    return false;
  }
  return a === b;
}

const feats = features();
const rows = [];
let evaluations = 0;
let mismatches = 0;
const rejected = [];
for (const [e, type = "value", state] of CASES) {
  const text = JSON.stringify(e);
  const ml = createExpression(e, "layers[0].paint.x", SPEC(type), state);
  const ours = ZOOMS.map((z) => expr_eval(text, type, z, feats, JSON.stringify(state ?? {})));
  if (ml.result === "error") {
    if (typeof ours[0] === "string") continue;
    rejected.push(text);
    if (!MAPLIBRE_REJECTS.includes(text)) rows.push({ expression: text, type, problem: `MapLibre rejects it: ${ml.value[0].message}` });
    continue;
  }
  if (typeof ours[0] === "string") {
    rows.push({ expression: text, type, problem: `mbmap rejects it: ${ours[0]}` });
    continue;
  }
  let bad = 0;
  let sample = null;
  ZOOMS.forEach((zoom, zi) => {
    feats.forEach((f, i) => {
      let want;
      try {
        want = maplibreValue(ml.value.evaluateWithoutErrorHandling({ zoom }, f, undefined, f.canonical));
      } catch {
        want = { error: true };
      }
      evaluations++;
      if (!same(want, ours[zi][i])) {
        bad++;
        sample ??= { zoom, properties: f.properties, id: f.id, maplibre: want, mbmap: ours[zi][i] };
      }
    });
  });
  if (bad > 0) {
    mismatches += bad;
    rows.push({ expression: text, type, problem: `${bad} values differ`, sample });
  }
}

// Legacy filters: converted as style-spec converts them, and filtering as featureFilter does.
const legacyRows = [];
for (const f of LEGACY_FILTERS) {
  const text = JSON.stringify(f);
  const ours = legacy.convertFilter(f);
  if (JSON.stringify(ours) !== JSON.stringify(convertFilter(f))) {
    legacyRows.push({ filter: text, problem: `converted to ${JSON.stringify(ours)}, style-spec gives ${JSON.stringify(convertFilter(f))}` });
    continue;
  }
  const ml = featureFilter(f, "layers[0].filter");
  const results = expr_eval(JSON.stringify(ours), "boolean", 14, feats, "{}");
  if (typeof results === "string") {
    legacyRows.push({ filter: text, problem: `mbmap rejects the conversion: ${results}` });
    continue;
  }
  const bad = feats.filter((feature, i) => ml.filter({ zoom: 14 }, feature) !== (results[i] === true)).length;
  evaluations += feats.length;
  if (bad > 0) legacyRows.push({ filter: text, problem: `${bad} features filtered differently` });
}

// Legacy functions: converted as style-spec converts them; their values against MapLibre's own
// evaluation of the function (StylePropertyFunction), defaults applied as the property takes them.
const specOf = (name) => Object.entries(latest).find(([k, v]) => /^(paint|layout)_/.test(k) && v[name])?.[1][name];
for (const [name, fn] of LEGACY_FUNCTIONS) {
  const spec = specOf(name);
  const text = `${name}: ${JSON.stringify(fn)}`;
  const ours = legacy.convertFunction(fn, name);
  const theirs = convertFunction(fn, spec);
  if (JSON.stringify(ours) !== JSON.stringify(theirs) && !CONVERTED_OTHERWISE.includes(text)) {
    legacyRows.push({ function: text, problem: `converted to ${JSON.stringify(ours)}, style-spec gives ${JSON.stringify(theirs)}` });
    continue;
  }
  const ml = normalizePropertyExpression(fn, `layers[0].paint.${name}`, spec);
  const fallback = maplibreValue(normalizePropertyExpression(spec.default, `layers[0].paint.${name}`, spec).evaluate({ zoom: 0 }));
  let bad = 0;
  let sample = null;
  for (const zoom of ZOOMS) {
    const results = expr_eval(JSON.stringify(ours), spec.type, zoom, feats, "{}");
    if (typeof results === "string") {
      legacyRows.push({ function: text, problem: `mbmap rejects the conversion: ${results}` });
      break;
    }
    feats.forEach((f, i) => {
      const value = (v) => (v === null || v === undefined || v?.error || (typeof v === "number" && Number.isNaN(v)) ? fallback : v);
      const want = value(maplibreValue(ml.evaluate({ zoom }, f)));
      const got = value(results[i]);
      evaluations++;
      if (!same(want, got)) {
        bad++;
        sample ??= { zoom, properties: f.properties, maplibre: want, mbmap: got };
      }
    });
  }
  if (bad > 0) legacyRows.push({ function: text, problem: `${bad} values differ`, sample });
}

const summary = {
  expressions: CASES.length,
  "legacy filters": LEGACY_FILTERS.length,
  "legacy functions": LEGACY_FUNCTIONS.length,
  features: feats.length,
  zooms: ZOOMS.length,
  evaluations,
  "values that differ": mismatches,
  "rejected by MapLibre only (MAPLIBRE_REJECTS)": rejected.length,
  problems: rows.length + legacyRows.length,
};
console.table(summary);
for (const r of [...rows, ...legacyRows]) console.log(JSON.stringify(r));
await writeFile(
  path.join(ROOT, "bench/results/expression-golden.json"),
  `${JSON.stringify({ env: { "style-spec": "26.5.0 (from maplibre-gl 6.16.0)", node: process.version }, summary, problems: [...rows, ...legacyRows] }, null, 2)}\n`,
);
if (rows.length + legacyRows.length > 0) process.exit(1);
