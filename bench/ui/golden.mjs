// `mbmap/ui` vs MapLibre GL JS 6.16.0's controls in Chromium (bench/ui's page): scale bars, zoom
// buttons, attributions, geolocation (a fake Geolocation fed to both) and legend colors.
// Writes bench/results/ui-golden.json. Needs `npm --prefix npm run build`.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { fakeGeolocation } from "../lib/fake-geolocation.mjs";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";

const cameras = [
  { center: [139.7671, 35.6812], zoom: 12, bearing: 0, pitch: 0 },
  { center: [139.7671, 35.6812], zoom: 16.4, bearing: 40, pitch: 0 },
  { center: [141.35, 43.07], zoom: 7.3, bearing: 0, pitch: 50 },
  { center: [-70.6, -33.4], zoom: 3.1, bearing: -20, pitch: 0 },
  { center: [10, 78], zoom: 9, bearing: 0, pitch: 0 },
  { center: [0, 0], zoom: 1.2, bearing: 0, pitch: 0 },
];

const { server, origin } = await serve();
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
const results = {};
let failed = 0;
const check = (name, ok, detail) => {
  if (!ok) failed++;
  results[name] = { ok, ...detail };
};
try {
  const page = await browser.newPage({ viewport: { width: 800, height: 1200 } });
  page.on("pageerror", (e) => console.log("pageerror", e.message));
  await page.addInitScript(fakeGeolocation);
  await page.goto(`${origin}/bench/ui/index.html`);
  await page.waitForFunction(() => window.__ready, null, { timeout: 60000 });

  const scales = await page.evaluate((cameras) => {
    const out = [];
    for (const c of cameras) {
      window.__mb.jumpTo(c);
      window.__ml.jumpTo(c);
      for (const t of window.__theirs.scales()) {
        const m = window.__ui.measureScale(window.__mb, t.maxWidth, t.unit);
        out.push({ camera: c, unit: t.unit, theirs: [t.label, t.width], mine: [m.label, m.width] });
      }
    }
    return out;
  }, cameras);
  const scaleDiffs = scales.filter((s) => s.theirs[0] !== s.mine[0] || Math.abs(s.theirs[1] - s.mine[1]) > 1e-3);
  check("scale", scaleDiffs.length === 0, { cases: scales.length, differ: scaleDiffs.slice(0, 5) });

  const nav = await page.evaluate(() => {
    const out = [];
    for (const zoom of [18, 17.5, 0, 0.5]) {
      window.__mb.jumpTo({ center: [139.7671, 35.6812], zoom, bearing: 0, pitch: 0 });
      window.__ml.jumpTo({ center: [139.7671, 35.6812], zoom, bearing: 0, pitch: 0 });
      const s = window.__mine.nav.state;
      out.push({ zoom, theirs: window.__theirs.nav(), mine: { canZoomIn: s.canZoomIn, canZoomOut: s.canZoomOut } });
    }
    return out;
  });
  // At the constrained minimum MapLibre's zoom after `jumpTo` misses its own `getMinZoom(true)` by one
  // ulp, so its zoom-out button stays enabled there; mbmap's are equal and disable it.
  const known = (n) => n.zoom === 0 && n.theirs.canZoomOut && !n.mine.canZoomOut;
  check("navigation", nav.every((n) => known(n) || JSON.stringify(n.theirs) === JSON.stringify(n.mine)), { cases: nav, known: nav.filter(known).map((n) => n.zoom) });

  const attribution = [];
  for (const zoom of [8, 12, 15]) {
    attribution.push(
      await page.evaluate(async (zoom) => {
        const settled = Promise.all([window.__mb.once("idle"), new Promise((r) => window.__ml.once("idle", r))]);
        window.__mb.jumpTo({ center: [139.7671, 35.6812], zoom });
        window.__ml.jumpTo({ center: [139.7671, 35.6812], zoom });
        window.__ml.triggerRepaint();
        await settled;
        return { zoom, theirs: window.__theirs.attribution(), mine: window.__mine.attribution.state.text };
      }, zoom),
    );
  }
  check("attribution", attribution.every((a) => a.theirs === a.mine), { cases: attribution });

  // Geolocation: each step on both maps, then their states and cameras once both have settled. `same fix`
  // comes where the camera already is, which moves nothing; panning after it still lets go.
  const steps = ["start", "first fix", "moved", "user pans", "fix in background", "back to active", "user zooms", "timeout", "fix again", "same fix", "user pans again", "back again", "off", "on again", "denied"];
  const geo = [];
  for (const name of steps) {
    geo.push(
      await page.evaluate(async (name) => {
        const { __mb: mb, __ml: ml, __geo: g, __mine: mine, __theirs: theirs } = window;
        const both = (f) => [mb, ml].forEach(f);
        const trigger = () => (mine.geolocation.trigger(), theirs.geolocate.trigger());
        ({
          start: trigger,
          "first fix": () => g.push(139.7, 35.66, 120),
          moved: () => g.push(139.71, 35.67, 40),
          "user pans": () => both((m) => m.panBy([120, 40], { duration: 0 })),
          "fix in background": () => g.push(139.72, 35.68, 40),
          "back to active": trigger,
          "user zooms": () => both((m) => m.zoomTo(13, { duration: 0 })),
          timeout: () => g.fail(3),
          "fix again": () => g.push(139.73, 35.69, 30),
          "same fix": () => g.push(139.73, 35.69, 30),
          "user pans again": () => both((m) => m.panBy([-80, 30], { duration: 0 })),
          "back again": trigger,
          off: trigger,
          "on again": trigger,
          denied: () => g.fail(1),
        })[name]();
        // Both cameras' moves (fitBounds flies) have ended once neither is moving for a while.
        for (let quiet = 0; quiet < 10; ) {
          await new Promise((r) => setTimeout(r, 50));
          quiet = mb.isMoving() || ml.isMoving() ? 0 : quiet + 1;
        }
        const cam = (m) => ({ lng: m.getCenter().lng, lat: m.getCenter().lat, zoom: m.getZoom() });
        return { step: name, theirs: theirs.geolocation(), mine: mine.geolocation.state.status, mlCamera: cam(ml), mbCamera: cam(mb) };
      }, name),
    );
  }
  const camerasAgree = (g) => Math.abs(g.mlCamera.lng - g.mbCamera.lng) < 1e-7 && Math.abs(g.mlCamera.lat - g.mbCamera.lat) < 1e-7 && Math.abs(g.mlCamera.zoom - g.mbCamera.zoom) < 1e-7;
  check("geolocation", geo.every((g) => g.theirs === g.mine && camerasAgree(g)), { steps: geo });
  await page.close();

  // Legend swatches of bench/pages/basic's style: each item's color as MapLibre evaluates the
  // layer's paint for the same feature properties at the same zoom.
  const legendPage = await browser.newPage({ viewport: { width: 800, height: 1200 } });
  legendPage.on("pageerror", (e) => console.log("pageerror", e.message));
  await legendPage.goto(`${origin}/bench/ui/index.html?style=/bench/pages/basic/style.json`);
  await legendPage.waitForFunction(() => window.__ready, null, { timeout: 60000 });
  const legend = [];
  for (const zoom of [14, 15.5, 17.2]) {
    legend.push(
      ...(await legendPage.evaluate(async (zoom) => {
        const { __mb: mb, __ml: ml, __mine: mine, __theirs: theirs } = window;
        const settled = Promise.all([mb.once("idle"), new Promise((r) => ml.once("idle", r))]);
        mb.jumpTo({ center: [139.7671, 35.6812], zoom });
        ml.jumpTo({ center: [139.7671, 35.6812], zoom });
        ml.triggerRepaint();
        await settled;
        const color = { fill: "fill-color", line: "line-color", circle: "circle-color", symbol: "text-color", "fill-extrusion": "fill-extrusion-color" };
        const opacity = { fill: "fill-opacity", line: "line-opacity", circle: "circle-opacity", symbol: "text-opacity", "fill-extrusion": "fill-extrusion-opacity" };
        return mine.legend.state.entries.flatMap((e) =>
          e.items.map((item) => ({
            zoom,
            layer: e.id,
            label: item.label,
            mine: item.paint.color,
            theirs: theirs.color(e.id, color[e.type], opacity[e.type], item.category.properties),
          })),
        );
      }, zoom)),
    );
  }
  const legendDiffs = legend.filter((l) => l.mine.some((v, i) => Math.abs(v - l.theirs[i]) > 1e-6));
  check("legend", legend.length > 0 && legendDiffs.length === 0, { items: legend.length, differ: legendDiffs.slice(0, 5) });
  await legendPage.close();
} finally {
  await browser.close();
  server.close();
}
await writeFile(path.join(ROOT, "bench/results/ui-golden.json"), JSON.stringify({ env: { maplibre: "6.16.0", browser: "chromium", viewport: "800x600" }, results }, null, 2) + "\n");
for (const [name, r] of Object.entries(results)) console.log(name, r.ok ? "ok" : "DIFFERS", JSON.stringify(r).slice(0, 600));
if (failed) process.exit(1);
