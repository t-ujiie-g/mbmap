// Writes the pack test's point cloud, bench/npm/pages/pointcloud/cloud.las: LAS 1.2, point format 2
// (16-bit colors), EPSG:6677 (JGD2011 plane rectangular IX) by its GeoTIFF keys, about 50,000 points
// around Tokyo Station: a 200 m ground grid (class 2) and five colored boxes (class 6) on it.
// Usage: node las/synthetic.mjs
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import proj4 from "proj4";
import { ROOT } from "../lib/root.mjs";
import { geoKeys, writeLas } from "./write.mjs";

const TOKYO_STATION = [139.7671, 35.6812];
const PLANE = "+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs";
const GROUND = 3;
const SCALE = 0.001;

const [cx, cy] = proj4("EPSG:4326", PLANE, TOKYO_STATION).map((v) => Math.round(v));
const offset = [cx, cy, 0];
const points = [];
const add = (x, y, z, rgb, classification) =>
  points.push({ x: Math.round(x / SCALE), y: Math.round(y / SCALE), z: Math.round(z / SCALE), intensity: 100 + classification * 10, returns: 1 | (1 << 3), classification, rgb: rgb.map((c) => c * 257) });

// Ground: every 1.25 m over 200 m, a checker of two grays.
for (let i = 0; i <= 160; i++) {
  for (let j = 0; j <= 160; j++) {
    const shade = (Math.floor(i / 16) + Math.floor(j / 16)) % 2 ? 150 : 110;
    add(-100 + i * 1.25, -100 + j * 1.25, GROUND, [shade, shade + 10, shade], 2);
  }
}

// Boxes: center x, y, half sizes, height and color; walls and roofs every 1 m.
const BOXES = [
  [-50, -40, 15, 10, 30, [220, 60, 50]],
  [40, -45, 12, 18, 45, [60, 120, 220]],
  [-35, 50, 20, 12, 20, [240, 200, 40]],
  [45, 45, 10, 10, 60, [70, 180, 90]],
  [0, 0, 8, 25, 15, [200, 90, 200]],
];
for (const [x, y, hx, hy, h, rgb] of BOXES) {
  for (let z = GROUND + 1; z <= GROUND + h; z += 1) {
    for (let t = -hx; t <= hx; t += 1) {
      add(x + t, y - hy, z, rgb, 6);
      add(x + t, y + hy, z, rgb, 6);
    }
    for (let t = -hy + 1; t < hy; t += 1) {
      add(x - hx, y + t, z, rgb, 6);
      add(x + hx, y + t, z, rgb, 6);
    }
  }
  for (let s = -hx + 1; s < hx; s += 1) for (let t = -hy + 1; t < hy; t += 1) add(x + s, y + t, GROUND + h, rgb.map((c) => Math.min(255, c + 30)), 6);
}

const bytes = writeLas({ minor: 2, format: 2, points, scale: [SCALE, SCALE, SCALE], offset, vlrs: [geoKeys([[1024, 1], [3072, 6677]])] });
const out = path.join(ROOT, "bench/npm/pages/pointcloud/cloud.las");
await mkdir(path.dirname(out), { recursive: true });
await writeFile(out, bytes);
console.log(`${out}: ${points.length} points, ${bytes.length} bytes`);
