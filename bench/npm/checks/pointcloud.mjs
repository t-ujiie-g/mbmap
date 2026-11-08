// mbmap/3d's point cloud layer on bench/npm/pages/pointcloud: the synthetic LAS in plane rectangular IX
// (EPSG:6677) is read, taken to longitude and latitude, drawn by its colors and recolored by class and
// height; `crs` given by hand reads the same, and a missing file rejects `ready`.
import { decodePng } from "../../lib/png.mjs";
import { commonestShare } from "./pixels.mjs";

/** The screen's pixels, to tell two colorings apart. */
const shot = async (page) => decodePng(await page.screenshot()).rgba;
const differing = (a, b) => {
  let n = 0;
  for (let i = 0; i < a.length; i += 4) if (a[i] !== b[i] || a[i + 1] !== b[i + 1] || a[i + 2] !== b[i + 2]) n++;
  return n / (a.length / 4);
};

const drawn = (page) =>
  page.evaluate(async () => {
    for (let i = 0; i < 3; i++) {
      window.__map.triggerRepaint();
      await new Promise(requestAnimationFrame);
    }
  });

export async function pointCloudChecks(page) {
  await page.waitForFunction(() => window.__loaded !== undefined);
  const read = await page.evaluate(async () => {
    await window.__layer.ready;
    return { bounds: window.__layer.bounds, counts: window.__layer.counts };
  });
  await drawn(page);
  const rgb = await commonestShare(page);
  const before = await shot(page);
  await page.evaluate(() => window.__layer.setColor("classification"));
  await drawn(page);
  const recolored = differing(before, await shot(page));
  const again = await page.evaluate(async () => {
    const map = window.__map;
    map.removeLayer("cloud");
    const layer = window.__pointCloudLayer({ id: "byHand", url: new URL("./cloud.las", location.href).href, crs: 6677, color: "height", maxPoints: 1000 });
    map.addLayer(layer);
    await layer.ready;
    const missing = window.__pointCloudLayer({ id: "missing", url: new URL("./missing.las", location.href).href });
    const error = await missing.ready.then(() => null, (e) => String(e?.message ?? e));
    return { bounds: layer.bounds, counts: layer.counts, error };
  });
  await drawn(page);
  const height = await commonestShare(page);
  const [w, s, e, n] = read.bounds ?? [];
  const nearStation = w < 139.7671 && e > 139.7671 && s < 35.6812 && n > 35.6812 && e - w < 0.01 && n - s < 0.01;
  // Thinned to 1000 points, the bounds shrink by less than the grid's spacing.
  const same = again.bounds?.every((x, i) => Math.abs(x - read.bounds[i]) < 2e-5);
  const ok =
    nearStation && read.counts.file === read.counts.drawn && read.counts.file > 1000 && rgb < 0.97 && recolored > 0.05 &&
    same && again.counts.drawn <= 1000 && again.counts.file === read.counts.file && height < 0.995 && /404|missing/.test(again.error ?? "");
  return [ok, { read, rgb, recolored, again, height }];
}
