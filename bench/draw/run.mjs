// setData latency while a shape is drawn: mbmap (npm facade) vs MapLibre, in Chromium with the Metal GPU.
// Usage: node draw/run.mjs (after `npm --prefix npm run build`); writes bench/results/draw-setdata.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";

const { server, origin } = await serve();
// With vsync: the times are whole frames until the update is on screen.
const browser = await chromium.launch({ args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] });
const results = {};
for (const engine of ["mbmap", "maplibre"]) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
  page.on("pageerror", (e) => console.error(engine, e.message));
  await page.goto(`${origin}/bench/draw/index.html?engine=${engine}`);
  await page.waitForFunction(() => window.__results, null, { timeout: 300000 });
  results[engine] = await page.evaluate(() => window.__results);
  await page.close();
}
await browser.close();
server.close();
for (const engine of Object.keys(results)) {
  console.log(engine);
  console.table(results[engine].map((r) => ({ vertices: r.vertices, "median ms": r.median.toFixed(1), "p95 ms": r.p95.toFixed(1) })));
}
await writeFile(path.join(ROOT, "bench/results/draw-setdata.json"), `${JSON.stringify({ env: { browser: `chromium ${browser.version()}`, viewport: "1280x800", runs: 40 }, results }, null, 2)}\n`);
