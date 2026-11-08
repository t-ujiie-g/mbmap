// Writes the pack test's I3S point cloud layer (PCSL 2.0, bench/npm/pages/i3s/pcsl/layers/0/): a root of 5000
// points over four children of 10000 near Tokyo Station, LEPCC xyz, RGB and INTENSITY by Esri's encoder
// (bench/lepcc/upstream.mjs) and raw CLASS_CODE (2 ground, 6 blocks). Usage: node i3s/pcsl-synthetic.mjs
import { mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { eastNorthUp, toCartesian, toCartographic } from "../../npm/src/tiles/geo.ts";
import { ROOT } from "../lib/root.mjs";
import { buildUpstream, decodeUpstream, encodeIntensity, encodeRgb, encodeXyz } from "../lepcc/upstream.mjs";

const DIR = path.join(ROOT, "bench/npm/pages/i3s/pcsl/layers/0");
const CENTER = [139.7671, 35.6812, 40];
// lodThreshold is the effective area (index.pcsl.md "density-threshold"): FOOTPRINT m² a point in a leaf,
// the children's sum above. The root's 0.25 points per m² are 0.06 per px² at zoom 17 (0.485 m/px) and
// 3.8 at zoom 14 (3.88 m/px), so refining below 0.5 per px² draws the children only close up.
const FOOTPRINT = 0.5;
const CHILD_POINTS = 10000;
const ROOT_EVERY = 8;
// Max errors: about 4 cm across (in degrees) and 2 cm in height.
const MAX_XY = 4e-7;
const MAX_Z = 0.02;
const KEYS = { ELEVATION: "1", INTENSITY: "2", RGB: "4", CLASS_CODE: "8" };

// Mulberry32: the same points on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(2026);
const int = (n) => Math.floor(rand() * n);

const ORIGIN = toCartesian(CENTER[0], CENTER[1], CENTER[2]);
const FRAME = eastNorthUp(ORIGIN);
const ecef = (e, n, u) => [0, 1, 2].map((k) => ORIGIN[k] + FRAME[k] * e + FRAME[4 + k] * n + FRAME[8 + k] * u);
const GROUND = [[112, 122, 98], [124, 130, 108]];
const BLOCK_COLORS = [[214, 84, 64], [70, 130, 200], [236, 196, 70], [120, 180, 110], [180, 100, 190], [90, 200, 200], [240, 140, 60], [200, 200, 210]];

/** A quadrant's points in east, north, up meters from CENTER: a ground grid and two blocks' walls and roofs. */
function quadrant(sx, sy, q) {
  const pts = [];
  const add = (e, n, u, rgb, intensity, cls) => pts.push({ e, n, u, rgb, intensity, cls });
  const grid = 77;
  for (let i = 0; i < grid; i++) {
    for (let j = 0; j < grid; j++) {
      const e = sx * (5 + (i * 175) / grid + rand() * 0.5);
      const n = sy * (5 + (j * 175) / grid + rand() * 0.5);
      add(e, n, rand() * 0.1, GROUND[(i + j) % 2], 40 + int(40), 2);
    }
  }
  const blocks = [0, 1].map((k) => ({
    e: sx * (40 + k * 70 + rand() * 20), n: sy * (40 + ((k * 60) % 100) + rand() * 20),
    w: 20 + rand() * 15, d: 20 + rand() * 15, h: 15 + rand() * 60, color: BLOCK_COLORS[(2 * q + k) % BLOCK_COLORS.length],
  }));
  const left = CHILD_POINTS - pts.length;
  for (const [k, b] of blocks.entries()) {
    const each = k === 0 ? Math.floor(left / 2) : left - Math.floor(left / 2);
    const walls = 2 * (b.w + b.d) * b.h;
    const roof = b.w * b.d;
    for (let k = 0; k < each; k++) {
      let e, n, u;
      if (rand() * (walls + roof) < roof) {
        [e, n, u] = [b.e + (rand() - 0.5) * b.w, b.n + (rand() - 0.5) * b.d, b.h];
      } else {
        let t = rand() * 2 * (b.w + b.d);
        u = rand() * b.h;
        if (t < b.w) [e, n] = [b.e - b.w / 2 + t, b.n - b.d / 2];
        else if ((t -= b.w) < b.d) [e, n] = [b.e + b.w / 2, b.n - b.d / 2 + t];
        else if ((t -= b.d) < b.w) [e, n] = [b.e + b.w / 2 - t, b.n + b.d / 2];
        else [e, n] = [b.e - b.w / 2, b.n + b.d / 2 - (t - b.w)];
      }
      add(e, n, u, b.color, 150 + int(100), 6);
    }
  }
  return pts;
}

/** An oriented box around `pts` in the east, north, up frame at their middle: center in degrees and meters, half sizes, the frame's quaternion in ECEF. */
function obb(pts) {
  const lo = [Infinity, Infinity, Infinity];
  const hi = [-Infinity, -Infinity, -Infinity];
  for (const p of pts) {
    [p.e, p.n, p.u].forEach((v, k) => {
      lo[k] = Math.min(lo[k], v);
      hi[k] = Math.max(hi[k], v);
    });
  }
  const c = toCartographic(ecef((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2));
  const m = eastNorthUp(toCartesian(c[0], c[1], c[2]));
  const [m00, m10, m20, m01, m11, m21, m02, m12, m22] = [m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]];
  const w = Math.sqrt(Math.max(0, 1 + m00 + m11 + m22)) / 2;
  const quaternion = [(m21 - m12) / (4 * w), (m02 - m20) / (4 * w), (m10 - m01) / (4 * w), w];
  return { center: c, halfSize: [0, 1, 2].map((k) => (hi[k] - lo[k]) / 2 + 0.5), quaternion };
}

/** Encodes a node's points; LEPCC stores them in an order of its own, which the attributes follow. */
function encode(pts) {
  const xyz = new Float64Array(pts.length * 3);
  pts.forEach((p, i) => xyz.set(toCartographic(ecef(p.e, p.n, p.u)), i * 3));
  const { blob, order } = encodeXyz(xyz, MAX_XY, MAX_XY, MAX_Z);
  const sorted = Array.from(order, (i) => pts[i]);
  const rgb = new Uint8Array(pts.length * 3);
  sorted.forEach((p, i) => rgb.set(p.rgb, i * 3));
  return {
    geometry: blob,
    [KEYS.RGB]: encodeRgb(rgb),
    [KEYS.INTENSITY]: encodeIntensity(Uint16Array.from(sorted, (p) => p.intensity)),
    [KEYS.CLASS_CODE]: Uint8Array.from(sorted, (p) => p.cls),
    xyz,
  };
}

await buildUpstream();
const children = [[1, 1], [-1, 1], [-1, -1], [1, -1]].map(([sx, sy], q) => quadrant(sx, sy, q));
const all = children.flat();
const rootPoints = all.filter((_, i) => i % ROOT_EVERY === 0);
const leafThreshold = CHILD_POINTS * FOOTPRINT;

await rm(DIR, { recursive: true, force: true });
const nodes = [];
let bytes = 0;
const lo = [Infinity, Infinity, Infinity];
const hi = [-Infinity, -Infinity, -Infinity];
for (const [resourceId, pts] of [rootPoints, ...children].entries()) {
  const enc = encode(pts);
  const check = decodeUpstream([{ kind: "xyz", blob: enc.geometry }, { kind: "rgb", blob: enc[KEYS.RGB] }, { kind: "intensity", blob: enc[KEYS.INTENSITY] }]);
  if (check.some((r) => r.status !== 0 || r.count !== pts.length)) throw new Error(`node ${resourceId}: a blob does not decode`);
  for (let i = 0; i < enc.xyz.length; i++) {
    lo[i % 3] = Math.min(lo[i % 3], enc.xyz[i]);
    hi[i % 3] = Math.max(hi[i % 3], enc.xyz[i]);
  }
  const dir = path.join(DIR, "nodes", String(resourceId));
  await mkdir(path.join(dir, "geometries"), { recursive: true });
  await writeFile(path.join(dir, "geometries/0"), enc.geometry);
  bytes += enc.geometry.length;
  for (const key of [KEYS.RGB, KEYS.INTENSITY, KEYS.CLASS_CODE]) {
    await mkdir(path.join(dir, "attributes", key), { recursive: true });
    await writeFile(path.join(dir, "attributes", key, "0"), enc[key]);
    bytes += enc[key].length;
  }
  const leaf = resourceId > 0;
  nodes.push({
    resourceId,
    firstChild: leaf ? 0 : 1,
    childCount: leaf ? 0 : 4,
    vertexCount: pts.length,
    obb: obb(pts),
    lodThreshold: leaf ? leafThreshold : 4 * leafThreshold,
  });
}
await mkdir(path.join(DIR, "nodepages"), { recursive: true });
await writeFile(path.join(DIR, "nodepages/0"), JSON.stringify({ nodes }));

const extent = [lo[0], lo[1], hi[0], hi[1]];
const layer = {
  id: 0,
  layerType: "PointCloud",
  name: "Synthetic point cloud",
  alias: "Synthetic point cloud",
  desc: "mbmap test data: a ground grid and colored blocks near Tokyo Station",
  copyrightText: "mbmap test data",
  capabilities: ["View"],
  spatialReference: { wkid: 4326, latestWkid: 4326 },
  heightModelInfo: { heightModel: "ellipsoidal", vertCRS: "WGS_84", heightUnit: "meter" },
  store: {
    id: "",
    profile: "PointCloud",
    version: "2.0",
    extent,
    index: { nodeVersion: 1, boundingVolumeType: "obb", nodesPerPage: 64, lodSelectionMetricType: "density-threshold" },
    defaultGeometrySchema: {
      geometryType: "points",
      header: [],
      topology: "PerAttributeArray",
      encoding: "lepcc-xyz",
      vertexAttributes: { position: { valueType: "Float64", valuesPerElement: 3 } },
      ordering: ["position"],
    },
  },
  attributeStorageInfo: [
    { key: KEYS.ELEVATION, name: "ELEVATION", encoding: "embedded-elevation" },
    { key: KEYS.INTENSITY, name: "INTENSITY", ordering: ["attributeValues"], attributeValues: { valueType: "UInt16", valuesPerElement: 1 }, encoding: "lepcc-intensity" },
    { key: KEYS.RGB, name: "RGB", ordering: ["attributeValues"], attributeValues: { valueType: "UInt8", valuesPerElement: 3 }, encoding: "lepcc-rgb" },
    { key: KEYS.CLASS_CODE, name: "CLASS_CODE", ordering: ["attributeValues"], attributeValues: { valueType: "UInt8", valuesPerElement: 1 } },
  ],
  fields: [
    { name: "ELEVATION", type: "esriFieldTypeDouble", alias: "ELEVATION" },
    { name: "INTENSITY", type: "esriFieldTypeInteger", alias: "INTENSITY" },
    { name: "RGB", type: "esriFieldTypeString", alias: "RGB" },
    { name: "CLASS_CODE", type: "esriFieldTypeSmallInteger", alias: "CLASS_CODE" },
  ],
  drawingInfo: {
    renderer: { type: "pointCloudRGBRenderer", field: "RGB", pointsPerInch: 25, pointSizeAlgorithm: { type: "pointCloudSplatAlgorithm", scaleFactor: 1, minSize: 4 } },
  },
  elevationInfo: { mode: "absoluteHeight" },
};
await writeFile(path.join(DIR, "layer.json"), JSON.stringify(layer, null, 1) + "\n");
console.log(`pcsl: ${nodes.length} nodes, ${rootPoints.length} + 4 × ${CHILD_POINTS} points, ${bytes} bytes of resources; lodThreshold ${4 * leafThreshold} (root), ${leafThreshold} (children)`);
