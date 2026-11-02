// Screen positions on terrain, mbmap against MapLibre GL JS 6.16.0 in Chromium
// (bench/query's page, the same DEM tiles and camera): `project` and the
// `covered` flag of `Map.track` against MapLibre's `project` and
// `isLocationOccluded` (what its Marker fades by), and `unproject`. The DEM is
// bench/fixtures/gsi-dem-fuji as Terrarium PNGs, which both engines read.
// Only places on terrain MapLibre draws from the DEM count: it covers distant
// ground with tiles below the DEM's minzoom and draws them flat, where mbmap
// takes the DEM's heights.
// Writes bench/results/track-golden.json. Needs `npm --prefix npm run build`.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { fujiTerrainStyle } from "../lib/fuji-terrain.mjs";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";

const style = await fujiTerrainStyle();
await writeFile(path.join(ROOT, "bench/dist/track-style.json"), JSON.stringify(style));

const fuji = [138.7274, 35.3606];
const cameras = {
  top: { center: fuji, zoom: 12.5, bearing: 0, pitch: 0 },
  tilted: { center: fuji, zoom: 12.2, bearing: 30, pitch: 60 },
  // Looking across the summit from its south-east flank: the far side is hidden.
  flank: { center: [138.76, 35.33], zoom: 13, bearing: -40, pitch: 75 },
  low: { center: [138.70, 35.31], zoom: 13.5, bearing: 20, pitch: 80 },
};
// Projected points may differ by this many CSS pixels, unprojected ones by
// this many meters (rounding: both sample the same DEM pixels).
const LIMITS = { px: 1e-6, meters: 1e-3 };
const COLS = 17, ROWS = 13;

const { server, origin } = await serve();
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
const results = [];
let failed = 0;
try {
  for (const [name, camera] of Object.entries(cameras)) {
    const page = await browser.newPage({ viewport: { width: 800, height: 1200 } });
    page.on("pageerror", (e) => console.log(name, "pageerror", e.message));
    await page.goto(`${origin}/bench/query/index.html?style=/bench/dist/track-style.json&camera=${encodeURIComponent(JSON.stringify(camera))}`);
    await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });
    const r = await page.evaluate(async ({ COLS, ROWS }) => {
      const mb = window.__mb, ml = window.__ml;
      const transform = ml._camera?.transform ?? ml.transform;
      const L = window.__maplibregl;
      const drawn = (ll) => ml.terrain.getDrawnElevationForLngLat(new L.LngLat(ll[0], ll[1])) !== undefined;
      // Places: what MapLibre shows on a grid of screen points, and a grid of places around the summit.
      const places = [];
      for (let j = 0; j < ROWS; j++)
        for (let i = 0; i < COLS; i++) {
          const p = ml.unproject([(i + 0.5) * 800 / COLS, (j + 0.5) * 600 / ROWS]);
          places.push([p.lng, p.lat]);
        }
      for (let j = 0; j < 11; j++) for (let i = 0; i < 11; i++) places.push([138.68 + i * 0.01, 35.31 + j * 0.01]);
      const tracked = places.map((ll) => {
        let at;
        mb.track(ll, (p) => (at = p)).remove();
        return at;
      });
      const project = [], covered = [];
      places.forEach((ll, k) => {
        const a = ml.project(ll), b = tracked[k];
        project.push(Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y)));
        covered.push([transform.isLocationOccluded(new L.LngLat(ll[0], ll[1]), ml.terrain), b.covered, a.x >= 0 && a.y >= 0 && a.x <= 800 && a.y <= 600 && drawn(ll)]);
      });
      const unproject = [];
      for (let j = 0; j < ROWS; j++)
        for (let i = 0; i < COLS; i++) {
          const pt = [(i + 0.5) * 800 / COLS, (j + 0.5) * 600 / ROWS];
          const a = ml.unproject(pt), b = mb.unproject(pt);
          if (!drawn([a.lng, a.lat])) continue;
          const dy = (a.lat - b.lat) * 111320, dx = (a.lng - b.lng) * 111320 * Math.cos((a.lat * Math.PI) / 180);
          unproject.push(Math.hypot(dx, dy));
        }
      return { project, covered, unproject, centers: [ml.getCenter(), mb.getCenter(), ml.getZoom(), mb.getZoom()] };
    }, { COLS, ROWS });
    const onScreen = r.covered.filter((c) => c[2]);
    const agree = onScreen.filter((c) => c[0] === c[1]).length;
    const projectMax = Math.max(...r.project.filter((_, k) => r.covered[k][2]));
    const unprojectMax = Math.max(...r.unproject);
    const ok = agree === onScreen.length && projectMax <= LIMITS.px && unprojectMax <= LIMITS.meters;
    if (!ok) failed++;
    results.push({
      view: name, ok, places: onScreen.length, skipped: r.covered.length - onScreen.length, screenPoints: r.unproject.length, coveredByMapLibre: onScreen.filter((c) => c[0]).length,
      coveredAgree: agree, projectMaxPx: Number(projectMax.toPrecision(3)), unprojectMaxM: Number(unprojectMax.toPrecision(3)),
    });
    if (!ok) console.log(name, JSON.stringify(r.centers));
    await page.close();
  }
} finally {
  await browser.close();
  server.close();
}
await writeFile(path.join(ROOT, "bench/results/track-golden.json"), JSON.stringify({ env: { maplibre: "6.16.0", browser: "chromium", viewport: "800x600", dem: "bench/fixtures/gsi-dem-fuji as Terrarium, exaggeration 1.5" }, limits: LIMITS, results }, null, 2) + "\n");
for (const r of results) console.log(JSON.stringify(r));
if (failed) process.exit(1);
