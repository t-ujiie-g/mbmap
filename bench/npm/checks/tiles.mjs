// mbmap/3d's tiles layer on bench/npm/pages/tiles: the synthetic b3dm tileset (bench/tiles/synthetic.mjs)
// is refined into its four tiles up close, coarsened to its root from afar, and drawn on the globe;
// PLATEAU's Draco-compressed buildings around Tokyo Station are refined and drawn; a click picks a
// feature with its batch table's properties.
import { commonestShare } from "./pixels.mjs";

export async function tilesChecks(page) {
  await page.evaluate(() => window.__layer.ready);
  await page.evaluate(() => window.__settled());
  const close = await page.evaluate(() => window.__layer.selected.map((t) => t.path).sort());
  // A block under the screen's center, with its batch table's height; nothing in the sky.
  const picked = await page.evaluate(async () => [await window.__layer.queryFeature({ x: 400, y: 300 }), await window.__layer.queryFeature({ x: 5, y: 5 })]);
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
  // The fixture holds the tiles around Tokyo Station; heights are above the ellipsoid (geoid +36.7 m).
  const plateau = await page.evaluate(async () => {
    const url = new URL("/bench/fixtures/plateau-chiyoda/tileset.json", location.href).href;
    // CI's small pages run without the fixtures, as the terrain check does.
    if (!(await fetch(url, { method: "HEAD" })).ok) return { skipped: "no fixtures" };
    const map = window.__map;
    map.setProjection(null);
    map.removeLayer("blocks");
    const layer = window.__tilesLayer({ id: "plateau", url, height: -36.7 });
    map.addLayer(layer);
    window.__layer = layer;
    await layer.ready;
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 17, pitch: 50, bearing: -20 });
    await window.__settled();
    const hit = await layer.queryFeature({ x: 400, y: 300 });
    return { tiles: layer.selected.length, ready: layer.selected.every((t) => t.state === "ready"), city: hit?.properties.city_code, gml: typeof hit?.properties.gml_id };
  });
  const plateauBlank = await commonestShare(page);
  const ok =
    JSON.stringify(close) === JSON.stringify(["r/0", "r/1", "r/2", "r/3"]) && closeBlank < 0.8 &&
    close.includes(picked[0]?.tile) && typeof picked[0]?.properties.height === "number" && picked[1] === null &&
    JSON.stringify(far) === JSON.stringify(["r"]) &&
    globe.length > 0 && globeBlank < 0.99 &&
    (plateau.skipped !== undefined || (plateau.tiles >= 10 && plateau.ready && plateauBlank < 0.6 && plateau.city === "13101" && plateau.gml === "string"));
  return [ok, { close, picked, closeBlank, far, globe, globeBlank, plateau, plateauBlank }];
}
