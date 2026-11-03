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

/** Whether two colours differ by at most `d` in each channel. */
export const near = (rgb, want, d = 3) => rgb.every((v, i) => Math.abs(v - want[i]) <= d);
