// Analysis bench in a module Worker per browser; writes bench/results/analysis-<browser>.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium, firefox, webkit } from "playwright";
import { bundle } from "../lib/bundle.mjs";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";
import { makeGeoJSONFixtures } from "../geojson/fixtures.mjs";
import { printAnalysis } from "./bench-core.mjs";

await makeGeoJSONFixtures();
await bundle("bench/analysis/worker.mjs", "bench/dist/analysis-worker.mjs", { platform: "browser" });
const { server, origin } = await serve();
const wanted = process.argv.slice(2);
for (const [name, type] of Object.entries({ chromium, firefox, webkit })) {
  if (wanted.length && !wanted.includes(name)) continue;
  const browser = await type.launch();
  const page = await browser.newPage();
  await page.goto(`${origin}/bench/lib/worker-page.html?worker=/bench/dist/analysis-worker.mjs`);
  const result = await page.evaluate(() => window.__result);
  result.env = { ...result.env, browser: name, version: browser.version() };
  await browser.close();
  await writeFile(path.join(ROOT, `bench/results/analysis-${name}.json`), JSON.stringify(result, null, 2) + "\n");
  console.log(`\n# ${name} ${result.env.version}`);
  if (result.error) console.log(result.error);
  else printAnalysis(result);
}
server.close();
