// mbmap/3d on bench/npm/pages/model: the model (meshopt-compressed, so through 3d.wasm) loads, stands at its points
// turned as `rotation` says, is lit by the style's `lights` as an extrusion is, casts shadows with them, and goes
// onto the globe (shadows too).
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
  // Shadows of a sun from the north 45° up (half ambient, half sun): the ground south of the 20 m block and of the
  // box (moved west) darkens by the sun's share of its light, 0.354 / 0.854, and is white farther off; the 5 m
  // roof south of the block has ambient light alone in its shadow, and the sun's too (cos 45°) beside it.
  const shadowLights = [light("ambient", 0.5), { ...light("directional", 0.5, [0, 45]), properties: { color: "#ffffff", intensity: 0.5, direction: [0, 45], "cast-shadows": true } }];
  const shadows = await page.evaluate(async (lights) => {
    const map = window.__map;
    map.setLights(lights);
    window.__layer.setData({ type: "Feature", properties: { turn: 0, size: [1, 1, 1] }, geometry: { type: "Point", coordinates: [139.766, 35.6812] } });
    await window.__settled();
    return [[139.7675, 35.68055], [139.7676, 35.6802], [139.766, 35.6809], [139.766, 35.6797], [139.7677, 35.68052], [139.7679, 35.68052]].map((p) => map.project(p));
  }, shadowLights);
  const shaded = await Promise.all(shadows.map((p) => pixel(page, p.x, p.y)));
  await page.evaluate(() => window.__map.setLights(null));
  const ground = Math.round(255 * (1 - 0.3536 / 0.8536));
  // Picking, lines of sight and measuring in 3D (bench/sight/golden.mjs checks them against the analytic answers):
  // the block's roof is 20 m up, a line at 10 m through it is blocked at its west face and one at 30 m is not; a
  // viewshed from the west at 10 m tints the ground before the block seen and behind it hidden.
  const sight = await page.evaluate(async () => {
    const map = window.__map;
    const { lineOfSight, measure3d } = await import("mbmap/3d");
    const roof = map.pickPosition(map.project([139.7676, 35.68075]));
    const blocked = lineOfSight(map, [139.7672, 35.68075, 10], [139.768, 35.68075, 10]);
    const clear = lineOfSight(map, [139.7672, 35.68075, 30], [139.768, 35.68075, 30]);
    const height = measure3d([[139.7672, 35.68075, 0], roof]).vertical;
    map.setViewshed({ position: [139.7668, 35.68075, 10], heading: 90, pitch: -10, horizontalFov: 60, verticalFov: 40, distance: 200 });
    await window.__settled();
    const points = [[139.7671, 35.68075], [139.7682, 35.68075]].map((p) => map.project(p));
    return { roof, blocked, clear, height, points };
  });
  const [before, behind] = await Promise.all(sight.points.map((p) => pixel(page, p.x, p.y)));
  await page.evaluate(() => window.__map.setViewshed(null));
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
  // On the globe (zoom 11, drawn as one), the 500 m block's shadow lies south of it, through the sphere's shadow map.
  const globeShadows = await page.evaluate(async (lights) => {
    const map = window.__map;
    map.setLights(lights);
    map.jumpTo({ center: [139.71, 35.69], zoom: 11 });
    window.__layer.setData({ type: "FeatureCollection", features: [] });
    await window.__settled();
    return [[139.71, 35.6978], [139.71, 35.685]].map((p) => map.project(p));
  }, shadowLights);
  const globeShaded = await Promise.all(globeShadows.map((p) => pixel(page, p.x, p.y)));
  const ok =
    square.slice(0, 2).every(red) && near(square[2], white) &&
    red(turned[0]) && near(turned[1], white) &&
    ["3d.js", "3d-worker.js"].every((f) => loaded.includes(f)) &&
    red(globe) && near(space, white) &&
    near(ambient[1], [32, 128, 192]) && red(ambient[0]) && half(ambient[0], halved[0]) && half(ambient[1], halved[1]) &&
    noon.length === 2 && red(noonPixel) &&
    near(shaded[0], [ground, ground, ground]) && near(shaded[1], white) && near(shaded[2], [ground, ground, ground]) && near(shaded[3], white) &&
    near(shaded[4], [16, 64, 96]) && near(shaded[5], [27, 109, 164]) &&
    near(globeShaded[0], [ground, ground, ground]) && near(globeShaded[1], white) &&
    Math.abs(sight.roof[2] - 20) < 0.05 && !sight.blocked.visible && Math.abs(sight.blocked.obstruction[0] - 139.7674) < 1e-6 &&
    sight.clear.visible && Math.abs(sight.height - 20) < 0.05 && before[1] > before[0] + 30 && behind[0] > behind[1] + 30;
  return [ok, { square, turned, loaded, globe, space, ambient, halved, noon, noonPixel, shaded, globeShaded, sight, before, behind }];
}
