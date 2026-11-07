// mbmap's evaluateExpression (the attribute table's field calculation) vs style-spec 26.5.0's
// createExpression(...).evaluate on GSI features as GeoJSON and hand-written ones: the value-typed expressions
// of style/expression-cases.mjs and field formulas, each value identical (colors and `format` as text).
// Usage: node fields/golden.mjs (after the npm build); writes bench/results/fields-golden.json.
import { readdirSync, readFileSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { VectorTile } from "@mapbox/vector-tile";
import { createExpression } from "@maplibre/maplibre-gl-style-spec";
import { PbfReader } from "pbf";
import { ROOT } from "../lib/root.mjs";
import { CASES, MAPLIBRE_REJECTS } from "../style/expression-cases.mjs";

const { evaluateExpression } = await import(pathToFileURL(path.join(ROOT, "npm/dist/index.js")).href);
const ZOOMS = [0, 14, 17.25];
const g = (k) => ["get", k];

function features() {
  const out = [];
  const dir = path.join(ROOT, "bench/fixtures/gsi-bvmap/14");
  const want = { label: 200, symbol: 200, contour: 100, railway: 100, road: 150, building: 150, waterarea: 20 };
  for (const x of readdirSync(dir).sort().slice(0, 2)) {
    for (const y of readdirSync(path.join(dir, x)).sort().slice(0, 2)) {
      const tile = new VectorTile(new PbfReader(readFileSync(path.join(dir, x, y))));
      for (const [name, max] of Object.entries(want)) {
        const layer = tile.layers[name];
        for (let i = 0; layer && i < Math.min(layer.length, max); i++) {
          const f = layer.feature(i).toGeoJSON(Number(x), parseInt(y), 14);
          out.push({ type: "Feature", properties: f.properties, geometry: f.geometry });
        }
      }
    }
  }
  out.forEach((f, i) => {
    if (i % 3 === 0) f.id = i % 2 ? i : `f${i}`;
  });
  const odd = [{}, { n: -0, s: "" }, { n: Infinity, s: " 12 " }, { n: 0.5, s: "1e3", b: true }, { n: 1e21, s: "#ff8000", b: false }, { n: 3, s: "Tōkyō 𠮷", z: null }, { s: "null", knj: "東京" }];
  for (const properties of odd) out.push({ type: "Feature", properties, geometry: { type: "Point", coordinates: [0, 0] }, id: "x" });
  return out;
}

// Field formulas a table would compute from GSI attributes.
const FORMULAS = [
  ["concat", g("knj"), "（", g("kana"), "）"],
  ["coalesce", g("knj"), g("name"), "名称なし"],
  ["*", ["to-number", g("alti"), 0], 3.28084],
  ["round", ["/", ["to-number", g("alti"), 0], 10]],
  ["number-format", ["to-number", g("alti"), 0], { "min-fraction-digits": 1, "max-fraction-digits": 1 }],
  ["number-format", ["to-number", g("vt"), 0], { locale: "ja-JP" }],
  ["match", ["to-string", g("ftCode")], ["2701", "2702"], "道路", ["7352", "7353"], "等高線", "その他"],
  ["case", [">", ["to-number", g("alti"), -1], 1000], "高い", [">", ["to-number", g("alti"), -1], 0], "低い", "不明"],
  ["step", ["to-number", g("rdCtg"), 0], "a", 1, "b", 3, "c"],
  ["interpolate", ["linear"], ["to-number", g("alti"), 0], 0, 0, 3776, 100],
  ["upcase", ["to-string", ["coalesce", g("kana"), ""]]],
  ["slice", ["to-string", ["coalesce", g("knj"), ""]], 0, 2],
  ["length", ["to-string", ["coalesce", g("knj"), ""]]],
  ["index-of", "区", ["to-string", ["coalesce", g("knj"), ""]]],
  ["to-string", ["id"]],
  ["concat", ["geometry-type"], ":", ["coalesce", ["id"], "-"]],
  ["has", "alti"],
  ["to-boolean", g("knj")],
  ["typeof", g("alti")],
  ["to-string", ["to-color", ["coalesce", g("s"), "red"]]],
  ["to-color", ["concat", "hsl(", ["%", ["to-number", g("ftCode"), 0], 360], ", 50%, 50%)"]],
  ["literal", [1, "a", true]],
  ["format", ["coalesce", g("knj"), ""], {}, "!", { "font-scale": 1.2 }],
  ["zoom"],
  ["*", ["zoom"], ["to-number", g("n"), 1]],
  ["^", 2, ["to-number", g("n"), 0]],
  ["sqrt", ["to-number", g("alti"), 0]],
  ["%", ["to-number", g("ftCode"), 0], 7],
  ["get", "missing"],
  ["/", ["to-number", g("n"), 0], 0],
];

/** style-spec's value as evaluateExpression gives it. */
function plain(v) {
  if (v === undefined || (typeof v === "number" && Number.isNaN(v))) return null;
  if (Array.isArray(v)) return v.map(plain);
  if (v && typeof v === "object") return typeof v.sensitivity === "string" ? null : String(v);
  return v;
}
const same = (a, b) => (Array.isArray(a) ? Array.isArray(b) && a.length === b.length && a.every((x, i) => same(x, b[i])) : Object.is(a, b));

const feats = features();
const problems = [];
let expressions = 0;
let evaluations = 0;
let differ = 0;
const quiet = console.warn;
console.warn = () => {};
for (const e of [...CASES.filter(([, type = "value", state]) => type === "value" && !state).map(([e]) => e), ...FORMULAS]) {
  const text = JSON.stringify(e);
  // within and distance need the feature's tile, which a table row has not.
  if (/"(within|distance|global-state|feature-state|line-progress|heatmap-density|elevation)"/.test(text)) continue;
  expressions++;
  const ml = createExpression(e, "layers[0].paint.x");
  let ours;
  try {
    ours = ZOOMS.map((zoom) => evaluateExpression(e, feats, { zoom }));
  } catch (err) {
    ours = err.message;
  }
  if (ml.result === "error") {
    if (typeof ours !== "string" && !MAPLIBRE_REJECTS.includes(text)) problems.push({ expression: text, problem: `style-spec rejects it: ${ml.value[0].message}` });
    continue;
  }
  if (typeof ours === "string") {
    problems.push({ expression: text, problem: ours });
    continue;
  }
  let bad = 0;
  let sample = null;
  ZOOMS.forEach((zoom, zi) =>
    feats.forEach((f, i) => {
      // As MapLibre gives a GeoJSON feature to expressions: its geometry's type.
      const want = plain(ml.value.evaluate({ zoom }, { type: f.geometry.type, properties: f.properties, ...(f.id === undefined ? {} : { id: f.id }) }));
      evaluations++;
      if (!same(want, ours[zi][i])) {
        bad++;
        sample ??= { zoom, properties: f.properties, id: f.id, styleSpec: want, mbmap: ours[zi][i] };
      }
    }),
  );
  if (bad) {
    differ += bad;
    problems.push({ expression: text, problem: `${bad} values differ`, sample });
  }
}
console.warn = quiet;

const summary = { expressions, features: feats.length, zooms: ZOOMS.length, evaluations, "values that differ": differ, problems: problems.length };
console.table(summary);
for (const p of problems.slice(0, 20)) console.log(JSON.stringify(p).slice(0, 600));
const ok = problems.length === 0;
await writeFile(path.join(ROOT, "bench/results/fields-golden.json"), JSON.stringify({ summary, problems, ok }, null, 2) + "\n");
console.log(ok ? "all identical" : `${problems.length} problems`);
process.exit(ok ? 0 : 1);
