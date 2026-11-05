// Pointer moves while a polygon is drawn over many shapes with mbmap/draw: per move, the time until
// the map is idle again, in Chromium with the Metal GPU (vsync: whole frames).
// Usage: node draw/many-run.mjs [--shapes=500] [--label=name]; writes bench/results/draw-many[-label].json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";
import { arg } from "../lib/args.mjs";

const shapes = Number(arg("shapes", 500));
const label = arg("label", "");
const { server, origin } = await serve();
const browser = await chromium.launch({ args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
page.on("pageerror", (e) => console.error(e.message));
await page.goto(`${origin}/bench/draw/many.html?shapes=${shapes}`);
await page.waitForFunction(() => window.__ready, null, { timeout: 120000 });
await page.mouse.click(300, 300);
await page.waitForTimeout(400);
await page.mouse.click(700, 320);
await page.waitForTimeout(400);
const times = [];
for (let i = 0; i < 41; i++) {
  await page.evaluate(() => {
    const t0 = performance.now();
    window.__done = new Promise((r) => window.__map.once("idle", () => r(performance.now() - t0)));
  });
  await page.mouse.move(600 + (i % 2) * 40, 500 + i * 3);
  const t = await page.evaluate(() => window.__done);
  if (i > 0) times.push(t);
}
await browser.close();
server.close();
const q = (p) => [...times].sort((a, b) => a - b)[Math.floor(p * (times.length - 1))];
const result = { shapes, vertices: shapes * 33, median: q(0.5), p95: q(0.95) };
console.log(result);
await writeFile(path.join(ROOT, `bench/results/draw-many${label ? `-${label}` : ""}.json`), `${JSON.stringify({ env: { browser: `chromium ${browser.version()}`, viewport: "1280x800", moves: 40 }, ...result }, null, 2)}\n`);
