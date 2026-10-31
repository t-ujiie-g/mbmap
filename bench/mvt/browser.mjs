// mvt decode bench in a module Worker per Playwright browser; writes
// bench/results/mvt-decode-<browser>.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { build } from "esbuild";
import { chromium, firefox, webkit } from "playwright";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";
import { printRows } from "./bench-core.mjs";

await build({
  entryPoints: [path.join(ROOT, "bench/mvt/worker.mjs")],
  bundle: true, format: "esm", platform: "browser", outfile: path.join(ROOT, "bench/dist/mvt-worker.mjs"),
  external: ["/_build/*"], logLevel: "warning",
});
const { server, origin } = await serve();
const wanted = process.argv.slice(2);
for (const [name, type] of Object.entries({ chromium, firefox, webkit })) {
  if (wanted.length && !wanted.includes(name)) continue;
  const browser = await type.launch();
  const page = await browser.newPage();
  await page.goto(`${origin}/bench/mvt/index.html`);
  const result = await page.evaluate(() => window.__result);
  result.env = { ...result.env, browser: name, version: browser.version() };
  await browser.close();
  await writeFile(path.join(ROOT, `bench/results/mvt-decode-${name}.json`), JSON.stringify(result, null, 2) + "\n");
  console.log(`\n# ${name} ${result.env.version}`);
  if (result.error) { console.log(result.error); continue; }
  printRows(result);
}
server.close();
