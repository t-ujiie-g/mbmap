// mbmap/3d on bench/npm/pages/model: the model loads through 3d.wasm (meshopt), stands at its points
// turned as `rotation` says, and goes onto the globe.
import { near, pixel } from "./pixels.mjs";

const white = [255, 255, 255];
const red = (c) => c[0] > 150 && c[1] < 90 && c[2] < 90;

export async function modelChecks(page) {
  await page.evaluate(() => window.__layer.ready);
  await page.evaluate(() => window.__settled());
  const at = await page.evaluate(() => [[139.7671, 35.6812], [139.7681, 35.6812]].map((p) => window.__map.project(p)));
  // Square on: the diagonal at (40, 40) px is inside, (0, 55) px outside; turned 45° the other way round.
  const square = [await pixel(page, at[0].x, at[0].y), await pixel(page, at[0].x + 40, at[0].y + 40), await pixel(page, at[0].x, at[0].y + 55)];
  const turned = [await pixel(page, at[1].x, at[1].y), await pixel(page, at[1].x + 40, at[1].y + 40), await pixel(page, at[1].x, at[1].y + 55)];
  const loaded = await page.evaluate(() => performance.getEntriesByType("resource").map((e) => e.name.split("/").pop()).filter((n) => /^3d|box/.test(n)));
  await page.evaluate(async () => {
    const map = window.__map;
    map.setProjection({ type: "globe" });
    map.jumpTo({ zoom: 3 });
    window.__layer.setData({ type: "Feature", properties: { turn: 0, size: [20000, 20000, 20000] }, geometry: { type: "Point", coordinates: [139.7671, 35.6812] } });
    await window.__settled();
  });
  const centre = await page.evaluate(() => window.__map.project([139.7671, 35.6812]));
  const globe = await pixel(page, centre.x, centre.y);
  const space = await pixel(page, 3, 3);
  const ok =
    square.slice(0, 2).every(red) && near(square[2], white) &&
    red(turned[0]) && near(turned[1], white) && red(turned[2]) &&
    ["3d.js", "3d-worker.js", "3d.wasm", "box.glb"].every((f) => loaded.includes(f)) &&
    red(globe) && near(space, white);
  return [ok, { square, turned, loaded, globe, space }];
}
