// The globe on bench/npm/pages/globe: space around it stays clear, the camera projects onto the sphere,
// a drag turns it and the wheel zooms, a flight ends in mercator at the target, and setProjection(null)
// flattens the map.
import { near, pixel } from "./pixels.mjs";

const white = [255, 255, 255];

export async function globeChecks(page) {
  await page.evaluate(() => window.__settled());
  const space = await pixel(page, 5, 5);
  const middle = await pixel(page, 400, 300);
  const r1 = await page.evaluate(() => {
    const map = window.__map;
    const c = map.project([139.7, 35.7]);
    const back = map.unproject([400, 300]);
    const far = map.unproject([5, 5]);
    return { projection: map.getProjection(), c: [c.x, c.y], back: [back.lng, back.lat], far: [far.lng, far.lat], bounds: map.getBounds().toArray() };
  });
  await page.mouse.move(400, 300);
  await page.mouse.down();
  await page.mouse.move(350, 300, { steps: 5 });
  await page.mouse.up();
  const dragged = await page.evaluate(() => window.__map.getCenter().lng);
  await page.mouse.wheel(0, -200);
  await page.waitForTimeout(400);
  const zoomed = await page.evaluate(() => window.__map.getZoom());
  const flown = await page.evaluate(async () => {
    const map = window.__map;
    const ended = map.once("moveend");
    map.flyTo({ center: [2.35, 48.85], zoom: 13, duration: 600 });
    await ended;
    await window.__settled();
    const c = map.getCenter();
    return [c.lng, c.lat, map.getZoom()];
  });
  const flatCorner = await pixel(page, 5, 5);
  const flat = await page.evaluate(async () => {
    const map = window.__map;
    map.jumpTo({ center: [139.7, 35.7], zoom: 1 });
    map.setProjection(null);
    await window.__settled();
    return { projection: map.getProjection(), zoom: map.getZoom() };
  });
  const flatSpace = await pixel(page, 5, 5);
  const ok =
    near(space, white) && !near(middle, white) &&
    r1.projection?.type === "globe" &&
    Math.abs(r1.c[0] - 400) < 1e-6 && Math.abs(r1.c[1] - 300) < 1e-6 &&
    Math.abs(r1.back[0] - 139.7) < 1e-6 && Math.abs(r1.back[1] - 35.7) < 1e-6 &&
    r1.bounds[0][0] < 139.7 && r1.bounds[1][0] > 139.7 &&
    dragged > 139.7 + 1 && zoomed > 1 &&
    Math.abs(flown[0] - 2.35) < 1e-6 && Math.abs(flown[1] - 48.85) < 1e-6 && flown[2] === 13 && !near(flatCorner, white) &&
    flat.projection === null && flat.zoom === 1 && !near(flatSpace, white);
  return ["globe", ok, { space, middle, ...r1, dragged, zoomed, flown, flatCorner, flat, flatSpace }];
}
