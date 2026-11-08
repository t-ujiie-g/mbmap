// mbmap/3d on bench/npm/pages/model: the model (meshopt-compressed, so through 3d.wasm) loads, stands at its points
// turned as `rotation` says, is lit by the style's `lights` as an extrusion is, and goes onto the globe.
import { near, pixel } from "./pixels.mjs";

const white = [255, 255, 255];
const red = (c) => c[0] > 150 && c[1] < 90 && c[2] < 90;

export async function modelChecks(page) {
  await page.evaluate(() => window.__layer.ready);
  await page.evaluate(() => window.__settled());
  const at = await page.evaluate(() => [[139.7671, 35.6812], [139.7681, 35.6812]].map((p) => window.__map.project(p)));
  // The box is about 96 px wide: square on, (-45, -45) px off is inside and (0, 60) outside; turned
  // 45°, (-45, -45) is outside.
  const look = (p, offsets) => Promise.all(offsets.map(([dx, dy]) => pixel(page, p.x + dx, p.y + dy)));
  const square = await look(at[0], [[0, 0], [-45, -45], [0, 60]]);
  const turned = await look(at[1], [[0, 0], [-45, -45]]);
  // The style's lights: ambient alone gives the colors as they are; a quarter ambient and half a sun 60° off
  // the zenith (cos 60° = 0.5) halve them, on the model's top and the extrusion's roof alike.
  const block = await page.evaluate(() => window.__map.project([139.7676, 35.68075]));
  const lit = async (lights) => {
    await page.evaluate(async (l) => {
      window.__map.setLights(l);
      await window.__settled();
    }, lights);
    return [await pixel(page, at[0].x, at[0].y), await pixel(page, block.x, block.y)];
  };
  const light = (type, intensity, direction) => ({ id: type, type, properties: { color: "#ffffff", intensity, ...(direction ? { direction } : {}) } });
  const ambient = await lit([light("ambient", 1)]);
  const halved = await lit([light("ambient", 0.25), light("directional", 0.5, [0, 60])]);
  // Noon in Tokyo by timeOfDayLights: lit, not black or white.
  const noon = await page.evaluate(async () => {
    const { timeOfDayLights } = await import("mbmap");
    window.__map.setLights(timeOfDayLights(Date.UTC(2026, 5, 21, 3), 139.7671, 35.6812));
    await window.__settled();
    return window.__map.getLights();
  });
  const noonPixel = await pixel(page, at[0].x, at[0].y);
  await page.evaluate(() => window.__map.setLights(null));
  const half = (a, b) => a.every((v, i) => Math.abs(v * 0.5 - b[i]) <= 2);
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
    red(turned[0]) && near(turned[1], white) &&
    ["3d.js", "3d-worker.js"].every((f) => loaded.includes(f)) &&
    red(globe) && near(space, white) &&
    near(ambient[1], [32, 128, 192]) && red(ambient[0]) && half(ambient[0], halved[0]) && half(ambient[1], halved[1]) &&
    noon.length === 2 && red(noonPixel);
  return [ok, { square, turned, loaded, globe, space, ambient, halved, noon, noonPixel }];
}
