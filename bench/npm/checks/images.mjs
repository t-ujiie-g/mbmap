// Style images on the npm example's map: a fill whose pattern is missing draws nothing and fires
// `styleimagemissing`; `addImage` draws it, `updateImage` replaces it, an id used twice fires
// `error`, and `hasImage` / `listImages` / `removeImage` keep track.
import { pixel } from "./pixels.mjs";
import { step } from "./step.mjs";

export async function imageChecks(page) {
  await step(page, "images: a missing pattern", `
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 });
    window.__missing = [];
    map.on("styleimagemissing", (e) => window.__missing.push(e.id));
    const [a, b] = [map.unproject([100, 300]), map.unproject([300, 100])];
    map.addSource("img", { type: "geojson", data: { type: "Polygon", coordinates: [[[a.lng, a.lat], [b.lng, a.lat], [b.lng, b.lat], [a.lng, b.lat], [a.lng, a.lat]]] } });
    map.addLayer({ id: "img", type: "fill", source: "img", paint: { "fill-pattern": "swatch", "fill-antialias": false } });`);
  const solid = (rgb) => `({ width: 2, height: 2, data: new Uint8Array([${rgb.join(",")},255].concat(...Array(3).fill([${rgb.join(",")},255]))) })`;
  const without = await pixel(page, 200, 200);
  const missing = await page.evaluate(() => window.__missing.slice());
  await step(page, "images: addImage", `map.addImage("swatch", ${solid([255, 0, 0])});`);
  const added = await pixel(page, 200, 200);
  const tracked = await page.evaluate(() => {
    const map = window.__map;
    const errors = [];
    const f = (e) => errors.push(e.error.message);
    map.on("error", f);
    map.addImage("swatch", { width: 1, height: 1, data: new Uint8Array(4) });
    map.addImage("bad", { width: 2, height: 2, data: new Uint8Array(4) });
    map.off("error", f);
    return { has: map.hasImage("swatch"), bad: map.hasImage("bad"), listed: map.listImages().includes("swatch"), errors };
  });
  await step(page, "images: updateImage", `map.updateImage("swatch", ${solid([0, 0, 255])});`);
  const updated = await pixel(page, 200, 200);
  const removed = await step(page, "images: removeImage", `
    map.removeImage("swatch");
    const gone = !map.hasImage("swatch");
    map.removeLayer("img");
    map.removeSource("img");
    return gone;`);
  const near = (rgb, want) => rgb.every((v, i) => Math.abs(v - want[i]) <= 3);
  const ok =
    !near(without, [255, 0, 0]) &&
    missing.includes("swatch") &&
    near(added, [255, 0, 0]) &&
    tracked.has && !tracked.bad && tracked.listed &&
    /already exists/.test(tracked.errors[0] ?? "") && /width \* height \* 4/.test(tracked.errors[1] ?? "") &&
    near(updated, [0, 0, 255]) &&
    removed;
  return { ok, without, missing, added, tracked, updated, removed };
}
