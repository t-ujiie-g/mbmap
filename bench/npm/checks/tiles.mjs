// mbmap/3d's tiles layer on bench/npm/pages/tiles: the synthetic b3dm tileset (bench/tiles/synthetic.mjs)
// is refined into its four tiles up close, coarsened to its root from afar, and drawn on the globe.
import { commonestShare } from "./pixels.mjs";

export async function tilesChecks(page) {
  await page.evaluate(() => window.__layer.ready);
  await page.evaluate(() => window.__settled());
  const close = await page.evaluate(() => window.__layer.selected.map((t) => t.path).sort());
  const closeBlank = await commonestShare(page);
  await page.evaluate(async () => {
    window.__map.jumpTo({ zoom: 12, pitch: 0 });
    await window.__settled();
  });
  const far = await page.evaluate(() => window.__layer.selected.map((t) => t.path).sort());
  await page.evaluate(async () => {
    window.__map.setProjection({ type: "globe" });
    window.__map.jumpTo({ zoom: 14, pitch: 45 });
    await window.__settled();
  });
  const globe = await page.evaluate(() => window.__layer.selected.map((t) => t.path).sort());
  const globeBlank = await commonestShare(page);
  const ok =
    JSON.stringify(close) === JSON.stringify(["r/0", "r/1", "r/2", "r/3"]) && closeBlank < 0.8 &&
    JSON.stringify(far) === JSON.stringify(["r"]) &&
    globe.length > 0 && globeBlank < 0.99;
  return [ok, { close, closeBlank, far, globe, globeBlank }];
}
