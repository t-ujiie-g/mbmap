// The showcase's Web services (mbmap/services, in the data tab): the bundled WMTS capabilities of GSI's pale map (its
// tiles from the fixtures with ?local=1) listed, one layer added under the vector overlays, kept by a new basemap, removed.
import { openTab } from "./step.mjs";

export async function showcaseServicesChecks(page) {
  await openTab(page, "data");
  await page.click("#services button >> text=地理院タイル（WMTS）を読む");
  await page.waitForFunction(() => window.__services.state.choices.length > 0);
  const choices = await page.evaluate(() => window.__services.state.choices.map((c) => c.title));
  await page.click("#services .service-layers button >> text=淡色地図");
  await page.waitForFunction(() => window.__services.state.items.length === 1);
  return page.evaluate(async () => {
    const map = window.__map;
    const id = window.__services.state.items[0].id;
    const source = map.getStyle().sources[id];
    const order = map.getLayersOrder();
    const under = order.indexOf(id) >= 0 && order.indexOf(id) < order.indexOf("places");
    let idle = map.once("idle");
    window.__panel.basemaps.select("photo");
    await idle;
    const kept = map.getLayer(id)?.type === "raster" && Boolean(map.getSource(id));
    idle = map.once("idle");
    window.__panel.basemaps.select("map");
    await idle;
    window.__services.remove(id);
    const gone = map.getSource(id) === undefined && window.__services.state.items.length === 0;
    const ok =
      JSON.stringify(window.__services.state.choices.map((c) => c.title)) === JSON.stringify(["淡色地図"]) &&
      source?.type === "raster" && /\/bench\/fixtures\/gsi-std\/\{z\}\/\{x\}\/\{y\}\.png$/.test(source.tiles[0]) && source.minzoom === 5 &&
      under && kept && gone;
    return { ok, id, tiles: source?.tiles, minzoom: source?.minzoom, under, kept, gone };
  }).then((r) => ({ ...r, choices }));
}
