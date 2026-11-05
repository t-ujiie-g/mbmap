// Screen checks of the pack test: pixels read from screenshots, and pins placed over the map.
import { decodePng } from "../../lib/png.mjs";

/** Whether a pin's `translate(xpx, ypx)` puts it at the 800 x 600 page's centre. */
export function atCentre(transform) {
  const m = /^translate\(([-\d.e]+)px, ([-\d.e]+)px\)$/.exec(transform ?? "");
  return !!m && Math.abs(Number(m[1]) - 400) < 0.01 && Math.abs(Number(m[2]) - 300) < 0.01;
}

/** The colour of screen pixel (x, y), read from a screenshot. */
export async function pixel(page, x, y) {
  const { rgba } = decodePng(await page.screenshot({ clip: { x: Math.round(x), y: Math.round(y), width: 1, height: 1 } }));
  return [rgba[0], rgba[1], rgba[2]];
}

/** The share of the page's pixels that have its commonest colour. */
export async function commonestShare(page) {
  const { rgba } = decodePng(await page.screenshot());
  const counts = new Map();
  for (let i = 0; i < rgba.length; i += 4) {
    const key = (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  return Math.max(...counts.values()) / (rgba.length / 4);
}

/** Whether two colours differ by at most `d` in each channel. */
export const near = (rgb, want, d = 3) => rgb.every((v, i) => Math.abs(v - want[i]) <= d);
