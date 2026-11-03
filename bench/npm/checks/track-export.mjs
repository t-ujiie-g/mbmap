// Tracking and export over a red raster tile (tileSourceChecks' red.png): a tracked place follows
// each frame and stops once removed; parts at 2x equal the whole image; bad sizes are refused.
import { near } from "./pixels.mjs";

export async function trackExportChecks(page) {
  const r = await page.evaluate(async () => {
    const map = window.__map;
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 });
    let idle = map.once("idle");
    map.addSource("e", { type: "raster", tiles: ["/bench/dist/pack/red.png"], tileSize: 256 });
    map.addLayer({ id: "e", type: "raster", source: "e" });
    await idle;
    const seen = [];
    const t = map.track([139.7671, 35.6812], (p) => seen.push(p));
    const atOnce = seen.length;
    let renders = 0;
    const counted = () => renders++;
    map.on("render", counted);
    idle = map.once("idle");
    map.panBy([100, 50], { duration: 0 });
    await idle;
    map.off("render", counted);
    const moved = seen.at(-1);
    t.setLngLat([139.7, 35.6]);
    const set = { at: t.getLngLat(), last: seen.at(-1) };
    t.remove();
    const before = seen.length;
    idle = map.once("idle");
    map.jumpTo({ center: [139.7671, 35.6812] });
    await idle;
    const pixels = async (blob) => {
      const bitmap = await createImageBitmap(blob);
      const ctx = new OffscreenCanvas(bitmap.width, bitmap.height).getContext("2d");
      ctx.drawImage(bitmap, 0, 0);
      return { width: bitmap.width, height: bitmap.height, data: ctx.getImageData(0, 0, bitmap.width, bitmap.height).data };
    };
    const whole = await pixels(await map.toBlob({ pixelRatio: 2 }));
    const parts = await pixels(await map.toBlob({ pixelRatio: 2, maxSize: 300 }));
    const same = whole.data.every((v, i) => v === parts.data[i]);
    const centre = [...whole.data.slice((600 * 1600 + 800) * 4, (600 * 1600 + 800) * 4 + 3)];
    const refused = [];
    for (const o of [{ pixelRatio: 0 }, { pixelRatio: 100 }]) await map.toBlob(o).catch((e) => refused.push(e.message));
    map.removeLayer("e");
    map.removeSource("e");
    return { first: seen[0], atOnce, moved, renders, set, after: seen.length - before, size: [whole.width, whole.height], same, centre, refused };
  });
  const ok =
    r.atOnce === 1 && Math.abs(r.first.x - 400) < 1e-6 && Math.abs(r.first.y - 300) < 1e-6 && r.first.covered === false &&
    Math.abs(r.moved.x - 300) < 1e-6 && Math.abs(r.moved.y - 250) < 1e-6 && r.renders > 0 &&
    r.set.at.lng === 139.7 && r.set.last.x < 0 &&
    r.after === 0 &&
    JSON.stringify(r.size) === "[1600,1200]" && r.same && near(r.centre, [255, 0, 0]) &&
    r.refused[0] === "mbmap: pixelRatio must be a positive number: 0" && r.refused[1] === "mbmap: cannot make a 80000 x 60000 image";
  return { ok, ...r };
}
