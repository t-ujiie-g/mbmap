// What a second wasm-gc module costs: gzip sizes, then per browser the time to
// start a worker, load each module and run the analysis cold and warm.
// Usage: node split/run.mjs [--runs=7] [browser...] (writes results/split.json)
import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { gzipSync } from "node:zlib";
import { chromium, firefox, webkit } from "playwright";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";
import { arg } from "../lib/args.mjs";

const runs = Number(arg("runs", 7));
const wanted = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const build = (pkg) => execFileSync("moon", ["build", pkg, "--target", "wasm-gc", "--release"], { cwd: ROOT, stdio: ["ignore", "ignore", "inherit"] });
const files = {
  worker: ["worker", "_build/wasm-gc/release/build/worker/worker.wasm"],
  combined: ["bench/split/combined_entry", "_build/wasm-gc/release/build/bench/split/combined_entry/combined_entry.wasm"],
  analysis: ["bench/split/analysis_entry", "_build/wasm-gc/release/build/bench/split/analysis_entry/analysis_entry.wasm"],
  empty: ["bench/split/empty_entry", "_build/wasm-gc/release/build/bench/split/empty_entry/empty_entry.wasm"],
};
const sizes = {};
for (const [name, [pkg, file]] of Object.entries(files)) {
  build(pkg);
  const bytes = await readFile(path.join(ROOT, file));
  sizes[name] = { raw: bytes.length, gzip: gzipSync(bytes, { level: 9 }).length };
}
console.table(sizes);

const { server, origin } = await serve();
const browsers = {};
for (const [name, type] of Object.entries({ chromium, firefox, webkit })) {
  if (wanted.length && !wanted.includes(name)) continue;
  const browser = await type.launch();
  const page = await browser.newPage();
  await page.goto(`${origin}/bench/split/index.html?runs=${runs}`);
  await page.waitForFunction(() => window.__result, null, { timeout: 300000, polling: 500 });
  const result = await page.evaluate(() => window.__result);
  browsers[name] = { version: browser.version(), ...result };
  await browser.close();
  console.log(`\n# ${name} ${browsers[name].version}`);
  if (result.error) console.log(result.error);
  else console.table(Object.fromEntries(Object.entries(result.modules).map(([m, r]) => [m, Object.fromEntries(Object.entries(r).map(([k, v]) => [k, v.toFixed(2)]))])));
}
server.close();
await writeFile(path.join(ROOT, "bench/results/split.json"), JSON.stringify({ env: { note: "local dev server, no HTTP cache" }, sizes, browsers }, null, 2) + "\n");
