// Gzip sizes of dist/ against the bundle budgets of VISION §2; exits 1 when
// one is exceeded. Writes bench/results/npm-size.json and appends a table to
// $GITHUB_STEP_SUMMARY when set.
import { appendFile, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";

const PKG = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const DIST = path.join(PKG, "dist");
const gz = async (f) => gzipSync(await readFile(path.join(DIST, f)), { level: 9 }).length;
const rows = [
  { name: "main (index.js)", bytes: await gz("index.js"), budget: 50_000 },
  { name: "element (element.js, on top of main)", bytes: await gz("element.js"), budget: 5_000 },
  { name: "worker (worker.js + mbmap.wasm)", bytes: (await gz("worker.js")) + (await gz("mbmap.wasm")), budget: 80_000 },
];
const kb = (n) => `${(n / 1000).toFixed(1)}KB`;
const lines = ["| bundle | gzip | budget |", "|---|---|---|", ...rows.map((r) => `| ${r.name} | ${kb(r.bytes)} | ${kb(r.budget)} |`)];
console.log(lines.join("\n"));
const version = JSON.parse(await readFile(path.join(PKG, "package.json"), "utf8")).version;
await writeFile(
  path.join(PKG, "../bench/results/npm-size.json"),
  JSON.stringify({ env: { package: `mbmap@${version}`, compression: "gzip -9" }, rows }, null, 2) + "\n",
);
if (process.env.GITHUB_STEP_SUMMARY) await appendFile(process.env.GITHUB_STEP_SUMMARY, `## Bundle sizes\n\n${lines.join("\n")}\n`);
const over = rows.filter((r) => r.bytes > r.budget);
if (over.length > 0) {
  console.error(`over budget: ${over.map((r) => r.name).join(", ")}`);
  process.exit(1);
}
