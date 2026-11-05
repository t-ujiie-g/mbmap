// The showcase's data tab (mbmap/data): the sample CSV drawn as points, a chosen file, a dataset kept
// across a new style, written out again, and an unreadable file reported in the panel.
import { awaitAfter, openTab } from "./step.mjs";

export async function showcaseDataChecks(page) {
  await openTab(page, "data");
  await awaitAfter(page, "data: sample", () => page.click("#data button >> text=サンプルを読む"), { event: "moveend" });
  await page.waitForFunction(() => window.__data.state.items.length === 1);
  const file = { type: "FeatureCollection", features: [{ type: "Feature", properties: { name: "線" }, geometry: { type: "LineString", coordinates: [[139.76, 35.68], [139.77, 35.69]] } }] };
  await page.setInputFiles("#data input[type=file]", { name: "line.geojson", mimeType: "application/geo+json", buffer: Buffer.from(JSON.stringify(file)) });
  await page.waitForFunction(() => window.__data.state.items.length === 2);
  await page.setInputFiles("#data input[type=file]", { name: "broken.geojson", mimeType: "application/geo+json", buffer: Buffer.from("{") });
  await page.waitForFunction(() => window.__data.state.error);
  const shown = await page.evaluate(() => document.querySelector(".data-error")?.textContent);
  await page.click("#data .datasets li:first-child button >> text=CSV");
  await page.waitForFunction(() => window.__written);
  const r = await page.evaluate(async () => {
    const map = window.__map;
    const items = window.__data.state.items.map((i) => [i.name, i.count]);
    let idle = map.once("idle");
    window.__panel.basemaps.select("photo");
    await idle;
    const kept = Boolean(map.getSource("data-1")) && map.getLayer("data-1-point") !== undefined;
    idle = map.once("idle");
    window.__panel.basemaps.select("map");
    await idle;
    const data = window.__data;
    for (const item of [...data.state.items]) data.remove(item.id);
    return { items, kept, written: window.__written, gone: map.getSource("data-1") === undefined };
  });
  const ok =
    r.items.length === 2 && r.items[0][1] === 5 && r.items[1][0] === "line.geojson" && r.items[1][1] === 1 && r.kept && r.gone &&
    r.written.format === "csv" && r.written.text.includes("日比谷公園") && shown?.includes("broken.geojson");
  return { ok, ...r, shown };
}
