// Style rendering vs MapLibre GL JS 6.16.0 in Chromium, pixel by pixel, a small style per scene
// (scenes.mjs) on the GSI fixtures; each scene's mean and p99 must stay within its limits.
// Usage: node style/golden.mjs [--scene=name] [--shots=dir]; writes bench/results/style-golden.json.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { decodePng } from "../lib/png.mjs";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";
import { SCENES } from "./scenes.mjs";
import { writeSprite } from "./sprite.mjs";

const arg = (k) => process.argv.find((a) => a.startsWith(`--${k}=`))?.split("=")[1];
const only = arg("scene");
const shots = arg("shots");
await mkdir(path.join(ROOT, "bench/dist/style"), { recursive: true });
if (shots) await mkdir(shots, { recursive: true });
await writeSprite();
const { server, origin } = await serve();
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
const results = [];
try {
  for (const [name, scene] of Object.entries(SCENES)) {
    if (only && name !== only) continue;
    const file = `bench/dist/style/${name}.json`;
    await writeFile(path.join(ROOT, file), JSON.stringify(scene.style));
    const page = await browser.newPage({ viewport: { width: 800, height: 1200 }, deviceScaleFactor: scene.dpr ?? 1 });
    page.on("pageerror", (e) => console.log(name, "pageerror", e.message));
    await page.goto(`${origin}/bench/query/index.html?style=/${file}&camera=${encodeURIComponent(JSON.stringify(scene.camera))}&ratio=${scene.dpr ?? 1}`);
    await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
    const shot = (y) => page.screenshot({ clip: { x: 0, y, width: 800, height: 600 } });
    const [pa, pb] = [await shot(0), await shot(600)];
    if (shots) {
      await writeFile(path.join(shots, `${name}-mbmap.png`), pa);
      await writeFile(path.join(shots, `${name}-maplibre.png`), pb);
    }
    const [a, b] = [decodePng(pa), decodePng(pb)];
    const diffs = new Uint8Array((a.rgba.length / 4) * 3);
    for (let i = 0, k = 0; i < a.rgba.length; i += 4) for (let c = 0; c < 3; c++) diffs[k++] = Math.abs(a.rgba[i + c] - b.rgba[i + c]);
    const sorted = diffs.slice().sort();
    const mean = sorted.reduce((s, d) => s + d, 0) / sorted.length;
    const p99 = sorted[Math.floor(sorted.length * 0.99)];
    const ok = mean <= scene.limits.mean && p99 <= scene.limits.p99;
    results.push({ scene: name, ok, mean: Number(mean.toFixed(3)), p99, limits: scene.limits, ...(scene.gap ? { gap: scene.gap } : {}) });
    await page.close();
  }
} finally {
  await browser.close();
  server.close();
}
console.table(results.map(({ limits, gap, ...r }) => ({ ...r, "mean limit": limits.mean, "p99 limit": limits.p99 })));
if (!only) await writeFile(path.join(ROOT, "bench/results/style-golden.json"), `${JSON.stringify({ env: { maplibre: "6.16.0", browser: "chromium", viewport: "800x600" }, results }, null, 2)}\n`);
if (results.some((r) => !r.ok)) process.exit(1);
