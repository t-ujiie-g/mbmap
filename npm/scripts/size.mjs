// Checks dist/ against VISION §2/§3's per-entry gzip budgets: every file belongs
// to one entry and each entry's JS references only its own files. Writes
// bench/results/npm-size.json (and $GITHUB_STEP_SUMMARY); exits 1 on failure.
import { appendFile, readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";
import { referencesOf } from "./references.mjs";

const PKG = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const DIST = path.join(PKG, "dist");

// `files` are what a user of the entry loads on top of the entries it builds
// on; `references` the dist files its JS may import or load by URL.
const ENTRIES = [
  { name: "mbmap", files: ["index.js"], budget: 50_000, references: ["./geojson.js", "./worker.js", "./mbmap.wasm"] },
  { name: "GeoJSON sources (loaded by mbmap when a style has one)", files: ["geojson.js"], budget: 5_000, references: ["./geojson-worker.js", "./geojson.wasm"] },
  { name: "mbmap/element (on top of mbmap)", files: ["element.js"], budget: 5_000, references: ["./index.js"] },
  { name: "display worker", files: ["worker.js", "mbmap.wasm"], budget: 100_000, references: [] },
  { name: "GeoJSON worker", files: ["geojson-worker.js", "geojson.wasm"], budget: 30_000, references: [] },
  { name: "mbmap/analysis", files: ["analysis.js"], budget: 5_000, references: ["./analysis-worker.js", "./analysis.wasm", "./geometry.wasm"] },
  { name: "analysis worker", files: ["analysis-worker.js", "analysis.wasm"], budget: 30_000, references: [] },
  { name: "geometry (loaded by the analysis worker on first use)", files: ["geometry.wasm"], budget: 45_000, references: [] },
];

const failures = [];
const owned = new Set(ENTRIES.flatMap((e) => e.files));
for (const f of await readdir(DIST)) {
  if (/\.(js|wasm)$/.test(f) && !owned.has(f)) failures.push(`${f} belongs to no entry (give it a budget in scripts/size.mjs)`);
}
const rows = [];
for (const e of ENTRIES) {
  let bytes = 0;
  for (const f of e.files) {
    const data = await readFile(path.join(DIST, f));
    bytes += gzipSync(data, { level: 9 }).length;
    if (f.endsWith(".js")) {
      for (const r of referencesOf(data.toString())) {
        if (!e.references.includes(r)) failures.push(`${e.name}: ${f} references ${r}`);
      }
    }
  }
  if (bytes > e.budget) failures.push(`${e.name}: ${bytes} bytes is over its budget of ${e.budget}`);
  rows.push({ name: e.name, bytes, budget: e.budget });
}

const kb = (n) => `${(n / 1000).toFixed(1)}KB`;
const lines = ["| entry | gzip | budget |", "|---|---|---|", ...rows.map((r) => `| ${r.name} | ${kb(r.bytes)} | ${kb(r.budget)} |`)];
console.log(lines.join("\n"));
const version = JSON.parse(await readFile(path.join(PKG, "package.json"), "utf8")).version;
await writeFile(
  path.join(PKG, "../bench/results/npm-size.json"),
  JSON.stringify({ env: { package: `mbmap@${version}`, compression: "gzip -9" }, rows }, null, 2) + "\n",
);
if (process.env.GITHUB_STEP_SUMMARY) await appendFile(process.env.GITHUB_STEP_SUMMARY, `## Bundle sizes\n\n${lines.join("\n")}\n`);
if (failures.length > 0) {
  for (const f of failures) console.error(f);
  process.exit(1);
}
