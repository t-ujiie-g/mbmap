// The showcase's analysis tab at Tokyo Station: the places' Voronoi cells classed by area (the
// legend lists the five classes), a route between two clicks along the drawn roads, the viewshed
// from the center and a line of sight to a click.
import { existsSync } from "node:fs";
import path from "node:path";
import { ROOT } from "../../lib/root.mjs";
import { openTab } from "./step.mjs";

export async function analyzeChecks(page) {
  const camera = await page.evaluate(() => ({ center: window.__map.getCenter(), zoom: window.__map.getZoom(), bearing: window.__map.getBearing(), pitch: window.__map.getPitch() }));
  await page.evaluate(() => window.__map.jumpTo({ center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 }));
  await page.evaluate(() => window.__map.once("idle"));
  await openTab(page, "analysis");
  const a = () => page.evaluate(() => window.__analysis.state);
  await page.click("#analysis-cells button >> nth=0");
  await page.waitForFunction(() => window.__analysis.state.cells?.breaks || window.__analysis.state.error, null, { timeout: 30_000 });
  await page.evaluate(() => window.__map.once("idle"));
  const cells = await page.evaluate(async () => {
    const s = window.__analysis.state;
    const legend = window.__panel.legend.state.entries.find((e) => e.id === "analysis-cells");
    const data = await window.__map.getSource("analysis-cells").getData();
    return {
      error: s.error, count: s.cells?.count, breaks: s.cells?.breaks, labels: legend?.items.map((i) => i.label),
      areas: data.features.map((f) => [f.properties.name, f.properties["面積"], f.properties["面積_km2"]]),
    };
  });
  // Two clicks east of the station (the panel covers the west), snapped to road vertices.
  const at = (lng, lat) => page.evaluate(([x, y]) => window.__map.project([x, y]), [lng, lat]);
  const box = await page.locator("#map, mb-map").first().boundingBox();
  const click = async (lng, lat) => {
    const p = await at(lng, lat);
    await page.mouse.click(box.x + p.x, box.y + p.y);
  };
  await page.click("#analysis-route button >> nth=0");
  await click(139.7676, 35.6795);
  await click(139.7705, 35.6830);
  await page.waitForFunction(() => { const r = window.__analysis.state.route; return r && r !== "loading"; }, null, { timeout: 30_000 });
  const route = (await a()).route;
  const routeLine = await page.evaluate(async () => (await window.__map.getSource("analysis-route").getData()).features.map((f) => f.geometry.type));
  await page.click("#analysis-sight button >> nth=0");
  await page.waitForFunction(() => { const s = window.__analysis.state.sight; return (s && s !== "loading") || window.__analysis.state.error; }, null, { timeout: 30_000 });
  const sight = (await a()).sight;
  const viewshed = await page.evaluate(() => ({ layer: window.__map.getLayer("analysis-viewshed")?.type, source: window.__map.getSource("analysis-viewshed")?.type }));
  await page.click("#analysis-sight button >> nth=1");
  await click(139.7705, 35.6830);
  await page.waitForFunction(() => window.__analysis.state.target, null, { timeout: 30_000 });
  const target = (await a()).target;
  const rows = await page.evaluate(() => ["cells", "route", "sight"].map((k) => document.getElementById(`analysis-${k}-rows`).textContent));
  // A click while picking does not identify.
  const picked = await page.evaluate(() => window.__identify?.state.point ?? null);
  for (const tool of ["cells", "route", "sight"]) await page.click(`#analysis-${tool} button >> text=消す`);
  const cleared = await page.evaluate(() => ({ layers: ["analysis-cells", "analysis-viewshed"].map((id) => Boolean(window.__map.getLayer(id))), state: window.__analysis.state }));
  await page.evaluate((c) => window.__map.jumpTo(c), camera);
  await page.evaluate(() => window.__map.once("idle"));
  // CI has no fixtures: no roads to route along, and the DEM tiles 404 as flat ground (everything seen).
  const fixtures = existsSync(path.join(ROOT, "bench/fixtures/gsi-bvmap/14"));
  const routed = fixtures ? route?.length > 100 && route.length < 2000 && routeLine.includes("LineString") : route?.error === "道路が見つかりません";
  const sorted = [...(cells.breaks ?? [])].every((b, i, xs) => i === 0 || b >= xs[i - 1]);
  const ok =
    !cells.error && cells.count >= 10 && cells.breaks?.length === 6 && sorted && cells.labels?.length === 5 &&
    cells.areas.every(([, m2, km2]) => m2 > 0 && km2 === Math.round(m2 / 10000) / 100) &&
    routed &&
    sight?.visible > 0 && sight.visible <= 1 && viewshed.layer === "raster" && viewshed.source === "canvas" &&
    typeof target?.visible === "boolean" && rows.every((r) => r.length > 0) &&
    JSON.stringify(cleared.layers) === JSON.stringify([false, false]) && cleared.state.cells === null && cleared.state.route === null && cleared.state.sight === null;
  return { ok, fixtures, cells, route, routeLine, sight, viewshed, target, rows, picked, cleared: cleared.layers };
}
