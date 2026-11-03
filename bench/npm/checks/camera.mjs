// The camera API on the npm example's map (Tokyo Station, 800 x 600): event
// order, animations ending where asked, fitting a box, projecting, limits and
// handlers, and the keyboard and double click as MapLibre has them.
import { awaitAfter } from "./step.mjs";

export async function cameraChecks(page) {
  const r = await page.evaluate(async () => {
    const map = window.__map;
    const log = [];
    for (const t of ["movestart", "move", "moveend", "zoomstart", "zoom", "zoomend", "rotatestart", "rotateend", "pitchstart", "pitchend"]) {
      map.on(t, () => {
        if (!log.includes(t)) log.push(t);
      });
    }
    const ended = () => map.once("moveend");
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 14, bearing: 0, pitch: 0 });
    log.length = 0;
    const easeEnd = ended();
    map.easeTo({ center: [139.78, 35.69], zoom: 15, bearing: 30, pitch: 20, duration: 300 });
    const moving = map.isMoving() && map.isEasing();
    await easeEnd;
    const eased = { ...map.getCenter(), zoom: map.getZoom(), bearing: map.getBearing(), pitch: map.getPitch() };
    const events = log.slice();
    const flyEnd = ended();
    map.flyTo({ center: [139.7, 35.65], zoom: 13, duration: 400 });
    await flyEnd;
    const flown = { ...map.getCenter(), zoom: map.getZoom() };
    const box = [[139.75, 35.66], [139.8, 35.7]];
    const want = map.cameraForBounds(box, { padding: 40 });
    const fitEnd = ended();
    map.fitBounds(box, { padding: 40, duration: 200 });
    await fitEnd;
    const fit = { ...map.getCenter(), zoom: map.getZoom(), want };
    const p = map.project([139.77, 35.68]);
    const back = map.unproject(p);
    const bounds = map.getBounds();
    const inBounds = bounds.getWest() < 139.77 && bounds.getEast() > 139.77 && bounds.getSouth() < 35.68 && bounds.getNorth() > 35.68;
    map.setMaxBounds([139.7, 35.6, 139.8, 35.7]);
    // Flat, since the bounds hold the center's half view (pitch aside, as in MapLibre).
    map.jumpTo({ center: [150, 20], zoom: 14, pitch: 0 });
    const clamped = map.getBounds();
    window.__clamped = clamped.toArray();
    const kept = clamped.getWest() >= 139.7 - 1e-9 && clamped.getEast() <= 139.8 + 1e-9 && clamped.getSouth() >= 35.6 - 1e-9 && clamped.getNorth() <= 35.7 + 1e-9;
    map.setMaxBounds(null);
    map.setMaxZoom(16);
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 18 });
    const capped = map.getZoom();
    map.setMaxZoom(22);
    map.scrollZoom.disable();
    const handlers = { scroll: map.scrollZoom.isEnabled(), drag: map.dragPan.isEnabled() };
    let badLimit = "";
    try {
      map.setMinZoom(30);
    } catch (e) {
      badLimit = e.message;
    }
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 14, bearing: 0, pitch: 0 });
    return { moving, eased, events, flown, fit, p, back, inBounds, kept, capped, handlers, badLimit };
  });
  // Scroll zoom is off: the wheel does nothing.
  await page.mouse.move(400, 300);
  await page.mouse.wheel(0, 300);
  await page.waitForTimeout(300);
  const wheel = await page.evaluate(() => window.__map.getZoom());
  // ArrowRight pans 100 px east and `+` zooms in by 1, each over 300 ms.
  const before = await page.evaluate(() => window.__map.project([139.7671, 35.6812]).x);
  await page.click("canvas", { position: { x: 400, y: 300 } });
  await awaitAfter(page, "camera: ArrowRight", () => page.keyboard.press("ArrowRight"), { event: "moveend" });
  const keyed = await page.evaluate(() => window.__map.project([139.7671, 35.6812]).x);
  await awaitAfter(page, "camera: +", () => page.keyboard.press("Equal"), { event: "moveend" });
  const plus = await page.evaluate(() => window.__map.getZoom());
  // A double click zooms in by 1 around the point clicked (in canvas pixels).
  const top = await page.evaluate(() => window.__map.getCanvas().getBoundingClientRect().top);
  const left = await page.evaluate(() => window.__map.getCanvas().getBoundingClientRect().left);
  const target = await page.evaluate(() => window.__map.unproject([600, 200]));
  await awaitAfter(page, "camera: double click", () => page.mouse.dblclick(left + 600, top + 200), { event: "moveend" });
  const dbl = await page.evaluate((t) => ({ zoom: window.__map.getZoom(), at: window.__map.project(t) }), target);
  const ok =
    r.moving &&
    Math.abs(r.eased.lng - 139.78) < 1e-9 && Math.abs(r.eased.lat - 35.69) < 1e-9 &&
    r.eased.zoom === 15 && r.eased.bearing === 30 && r.eased.pitch === 20 &&
    // The order of first appearance, as MapLibre fires them.
    JSON.stringify(r.events) === JSON.stringify(["movestart", "zoomstart", "rotatestart", "pitchstart", "move", "zoom", "zoomend", "rotateend", "pitchend", "moveend"]) &&
    Math.abs(r.flown.lng - 139.7) < 1e-9 && r.flown.zoom === 13 &&
    Math.abs(r.fit.lng - r.fit.want.center.lng) < 1e-9 && Math.abs(r.fit.zoom - r.fit.want.zoom) < 1e-9 &&
    Math.abs(r.back.lng - 139.77) < 1e-9 && Math.abs(r.back.lat - 35.68) < 1e-9 &&
    r.inBounds && r.kept && r.capped === 16 &&
    r.handlers.scroll === false && r.handlers.drag === true &&
    /zoom limits/.test(r.badLimit) &&
    wheel === 14 &&
    Math.abs(keyed - (before - 100)) < 1e-6 &&
    plus === 15 &&
    Math.abs(dbl.zoom - 16) < 1e-9 && Math.abs(dbl.at.x - 600) < 1e-6 && Math.abs(dbl.at.y - 200) < 1e-6;
  const clamped = await page.evaluate(() => window.__clamped);
  return { ok, ...r, clamped, wheel, before, keyed, plus, dbl };
}
