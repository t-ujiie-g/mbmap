// A synthetic sprite for the pattern scenes, at 1x and 2x: drawn by functions of the pixel so both
// sheets show the same picture, written to bench/dist/style/sprite{,@2x}.{json,png}.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { encodePng } from "../lib/png.mjs";
import { ROOT } from "../lib/root.mjs";

// Each image: its size in CSS pixels and its color at a point (u, v) in [0, 1) of it.
const IMAGES = {
  dots: { w: 12, h: 12, at: (u, v) => (Math.hypot(u - 0.5, v - 0.5) < 0.3 ? [200, 60, 40, 255] : [0, 0, 0, 0]) },
  stripes: { w: 16, h: 8, at: (u) => (u < 0.5 ? [40, 90, 200, 160] : [255, 255, 255, 60]) },
  checker: { w: 10, h: 10, at: (u, v) => ((u < 0.5) !== (v < 0.5) ? [30, 140, 70, 255] : [230, 220, 120, 255]) },
  odd: { w: 7, h: 5, at: (u, v) => [Math.round(u * 255), Math.round(v * 255), 128, 255] },
};

export async function writeSprite() {
  const dir = path.join(ROOT, "bench/dist/style");
  await mkdir(dir, { recursive: true });
  for (const ratio of [1, 2]) {
    const entries = Object.entries(IMAGES);
    const width = entries.reduce((s, [, i]) => s + i.w * ratio, 0);
    const height = Math.max(...entries.map(([, i]) => i.h * ratio));
    const rgba = new Uint8Array(width * height * 4);
    const index = {};
    let x0 = 0;
    for (const [name, img] of entries) {
      const w = img.w * ratio, h = img.h * ratio;
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) rgba.set(img.at((x + 0.5) / w, (y + 0.5) / h), (y * width + x0 + x) * 4);
      index[name] = { x: x0, y: 0, width: w, height: h, pixelRatio: ratio };
      x0 += w;
    }
    const suffix = ratio > 1 ? "@2x" : "";
    await writeFile(path.join(dir, `sprite${suffix}.png`), encodePng(width, height, rgba));
    await writeFile(path.join(dir, `sprite${suffix}.json`), JSON.stringify(index));
  }
}
