// Draws scenes with mbmap and MapLibre GL JS 6.16.0 in Chromium (bench/query/index.html: the same
// style and camera on both) and compares them pixel by pixel: each scene's per-channel mean and
// 99th percentile (0-255) against its limits. Shared by style/golden.mjs and style/public.mjs.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { decodePng } from "../lib/png.mjs";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";

export async function compareScenes(scenes, { only, shots, dir = "bench/dist/style" } = {}) {
  await mkdir(path.join(ROOT, dir), { recursive: true });
  if (shots) await mkdir(shots, { recursive: true });
  const { server, origin } = await serve();
  const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
  const browser = await chromium.launch({ args: gpu });
  const results = [];
  try {
    for (const [name, scene] of Object.entries(scenes)) {
      if (only && name !== only) continue;
      const file = `${dir}/${name}.json`;
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
  if (results.some((r) => !r.ok)) process.exitCode = 1;
  return results;
}
