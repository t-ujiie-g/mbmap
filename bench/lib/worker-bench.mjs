// Bundles a worker entry, runs it in a module Worker in each Playwright browser
// (or those named on the command line) and writes bench/results/<name>-<browser>.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium, firefox, webkit } from "playwright";
import { bundle } from "./bundle.mjs";
import { serve } from "./serve.mjs";
import { ROOT } from "./root.mjs";
import { printRows } from "./rows.mjs";

export async function runWorkerBench({ entry, name }) {
  await bundle(entry, `bench/dist/${name}-worker.mjs`, { platform: "browser" });
  const { server, origin } = await serve();
  const wanted = process.argv.slice(2);
  for (const [browserName, type] of Object.entries({ chromium, firefox, webkit })) {
    if (wanted.length && !wanted.includes(browserName)) continue;
    const browser = await type.launch();
    const page = await browser.newPage();
    await page.goto(`${origin}/bench/lib/worker-page.html?worker=/bench/dist/${name}-worker.mjs`);
    const result = await page.evaluate(() => window.__result);
    result.env = { ...result.env, browser: browserName, version: browser.version() };
    await browser.close();
    await writeFile(path.join(ROOT, `bench/results/${name}-${browserName}.json`), JSON.stringify(result, null, 2) + "\n");
    console.log(`\n# ${browserName} ${result.env.version}`);
    if (result.error) console.log(result.error);
    else printRows(result);
  }
  server.close();
}
