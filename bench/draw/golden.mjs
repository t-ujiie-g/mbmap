// mbmap/draw vs terra-draw 1.37 on MapLibre: the same clicks and moves in each mode, in Chromium,
// then the shapes compared. Usage: node draw/golden.mjs; writes bench/results/draw-golden.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import geodesic from "geographiclib-geodesic";
import { chromium } from "playwright";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";

const WGS84 = geodesic.Geodesic.WGS84;
// Each mode's input: ["click" | "move", x, y] in page pixels.
const SCRIPTS = {
  point: [["click", 400, 300]],
  linestring: [["click", 200, 200], ["move", 300, 250], ["click", 400, 200], ["click", 500, 400], ["move", 501, 401], ["click", 500, 400]],
  polygon: [["click", 200, 200], ["click", 500, 220], ["click", 450, 450], ["move", 230, 230], ["click", 205, 203]],
  rectangle: [["click", 250, 150], ["move", 400, 300], ["click", 550, 400]],
  circle: [["click", 400, 300], ["move", 450, 320], ["click", 520, 360]],
  freehand: [["click", 300, 300], ["move", 340, 300], ["move", 380, 320], ["move", 420, 360], ["move", 430, 420], ["move", 380, 450], ["move", 320, 430], ["move", 290, 380], ["click", 295, 340]],
};

const { server, origin } = await serve();
const browser = await chromium.launch({ args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] });
const drawn = {};
for (const engine of ["mbmap", "terradraw"]) {
  const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
  page.on("pageerror", (e) => console.error(engine, e.message));
  await page.goto(`${origin}/bench/draw/compare.html?engine=${engine}`);
  await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
  drawn[engine] = {};
  for (const [mode, script] of Object.entries(SCRIPTS)) {
    await page.evaluate((m) => (window.__clear(), window.__mode(m)), mode);
    await page.mouse.move(10, 10);
    for (const [kind, x, y] of script) {
      if (kind === "move") await page.mouse.move(x, y, { steps: 4 });
      else {
        await page.mouse.move(x, y, { steps: 4 });
        await page.mouse.click(x, y);
        // Clicks of a double click come closer than this (MapLibre's click tolerance is about time too).
        await page.waitForTimeout(350);
      }
    }
    await page.waitForFunction(() => window.__features().length > 0, null, { timeout: 5000 }).catch(() => {});
    drawn[engine][mode] = await page.evaluate(() => window.__features().map((f) => f.geometry));
  }
  await page.close();
}
await browser.close();
server.close();

const flat = (g) => (g.type === "Point" ? [g.coordinates] : g.type === "LineString" ? g.coordinates : g.coordinates[0]);
const maxDiff = (a, b) => (a.length === b.length ? Math.max(...a.map((p, i) => Math.hypot(p[0] - b[i][0], p[1] - b[i][1]))) : Infinity);
const corners = (ring) => ring.slice(0, -1).map((p) => p.map((v) => v.toFixed(9)).join()).sort();
const rows = [];
for (const mode of Object.keys(SCRIPTS)) {
  const [a, b] = [drawn.mbmap[mode], drawn.terradraw[mode]];
  const row = { mode, mbmap: a.length, terradraw: b.length, ok: a.length === 1 && b.length === 1 && a[0].type === b[0].type };
  if (row.ok) {
    const [pa, pb] = [flat(a[0]), flat(b[0])];
    row.vertices = `${pa.length} / ${pb.length}`;
    if (mode === "rectangle") {
      row.ok = JSON.stringify(corners(pa)) === JSON.stringify(corners(pb));
    } else if (mode === "circle") {
      // terra-draw ("globe") draws on a sphere; mbmap on WGS 84 at the geodesic distance to the click.
      const centre = drawn.mbmap.point[0].coordinates;
      const radius = (ring, at) => ring.slice(0, -1).map((p) => WGS84.Inverse(at[1], at[0], p[1], p[0]).s12);
      const ra = radius(pa, centre);
      const rb = radius(pb, centre);
      const mean = (xs) => xs.reduce((s, x) => s + x, 0) / xs.length;
      row.radius = `${mean(ra).toFixed(2)} m / ${mean(rb).toFixed(2)} m`;
      row.ok = pa.length === pb.length && Math.abs(mean(ra) - mean(rb)) / mean(rb) < 0.005;
    } else if (mode === "freehand") {
      row.ok = Math.abs(pa.length - pb.length) <= 1 && maxDiff([pa[0]], [pb[0]]) < 1e-7;
    } else {
      row.difference = maxDiff(pa, pb);
      row.ok = row.difference < 1e-7;
    }
  }
  rows.push(row);
}
console.table(rows);
await writeFile(path.join(ROOT, "bench/results/draw-golden.json"), `${JSON.stringify({ env: { "terra-draw": "1.37.0", adapter: "terra-draw-maplibre-gl-adapter 1.5.0", maplibre: "6.16.0" }, rows, drawn }, null, 2)}\n`);
process.exit(rows.every((r) => r.ok) ? 0 : 1);
