// Writes the pack test's I3S 3DObject layer near Tokyo Station (bench/npm/pages/i3s/set/layers/0/, resources
// at their REST paths): a gray root per block over four children, uncompressed and Draco buffers, a PNG on two
// children, attributes OBJECTID, name and height. Usage: node i3s/synthetic.mjs
import { mkdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { crc32, deflateSync } from "node:zlib";
import draco3d from "draco3d";
import { eastNorthUp, toCartesian, toCartographic } from "../../npm/src/tiles/geo.ts";
import { ROOT } from "../lib/root.mjs";

const DIR = path.join(ROOT, "bench/npm/pages/i3s/set/layers/0");
const CENTER = [139.7671, 35.6812, 0];
// Children switch in when the root's box covers more than 300 px across (maxScreenThresholdSQ is the area of that disk).
const ROOT_THRESHOLD = (Math.PI / 4) * 300 * 300;
const CHILD_THRESHOLD = (Math.PI / 4) * 3000 * 3000;

// Mulberry32: the same buildings on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = rng(31);

const NAMES = ["丸の内一丁目ビル", "Marunouchi North", "八重洲テラス", "Yaesu Gate", "日本橋口タワー", "Otemachi Place", "京橋スクエア", "Kyobashi Front", "有楽町ビル", "Yurakucho Hall", "東京駅南ビル", "Station South"];
// Buildings in east, north meters from the center: four blocks (NE, NW, SW, SE) of three each.
const BUILDINGS = [[1, 1], [-1, 1], [-1, -1], [1, -1]].flatMap(([sx, sy], block) =>
  [0, 1, 2].map((k) => {
    const id = block * 3 + k + 1;
    return {
      id, block, name: NAMES[id - 1],
      e: sx * (60 + k * 55 + rand() * 10), n: sy * (50 + ((k * 70) % 120) + rand() * 10),
      w: 25 + rand() * 15, d: 20 + rand() * 15, h: Math.round((20 + rand() * 120) * 10) / 10,
      color: [80 + Math.floor(rand() * 170), 80 + Math.floor(rand() * 170), 80 + Math.floor(rand() * 170), 255],
    };
  }),
);

const ORIGIN = toCartesian(CENTER[0], CENTER[1], CENTER[2]);
const FRAME = eastNorthUp(ORIGIN);
const ecef = (e, n, u) => [0, 1, 2].map((k) => ORIGIN[k] + FRAME[k] * e + FRAME[4 + k] * n + FRAME[8 + k] * u);
const turn = (e, n, u) => [0, 1, 2].map((k) => FRAME[k] * e + FRAME[4 + k] * n + FRAME[8 + k] * u);

/** A box's 12 triangles as 36 corners in east, north, up meters, each face's outward normal and uvs over the face. */
function box({ e, n, w, d, h }) {
  const [x0, x1, y0, y1] = [e - w / 2, e + w / 2, n - d / 2, n + d / 2];
  const faces = [
    [[x0, y0, 0], [x1, y0, 0], [x1, y0, h], [x0, y0, h], [0, -1, 0]],
    [[x1, y0, 0], [x1, y1, 0], [x1, y1, h], [x1, y0, h], [1, 0, 0]],
    [[x1, y1, 0], [x0, y1, 0], [x0, y1, h], [x1, y1, h], [0, 1, 0]],
    [[x0, y1, 0], [x0, y0, 0], [x0, y0, h], [x0, y1, h], [-1, 0, 0]],
    [[x0, y0, h], [x1, y0, h], [x1, y1, h], [x0, y1, h], [0, 0, 1]],
    [[x0, y1, 0], [x1, y1, 0], [x1, y0, 0], [x0, y0, 0], [0, 0, -1]],
  ];
  const corners = [];
  for (const [a, b, c, dd, normal] of faces) {
    const uv = [[0, 1], [1, 1], [1, 0], [0, 0]];
    for (const i of [0, 1, 2, 0, 2, 3]) corners.push({ p: [a, b, c, dd][i], normal, uv: uv[i] });
  }
  return corners;
}

/** A node's mesh: positions as I3S offsets (degrees for x and y, meters for z) from `center`, ECEF normals, uvs, colors and the feature table. */
function mesh(buildings, center, gray) {
  const pos = [], nor = [], uv = [], col = [], ids = [], ranges = [];
  let face = 0;
  for (const b of buildings) {
    const corners = box(b);
    for (const { p, normal, uv: t } of corners) {
      const g = toCartographic(ecef(...p));
      pos.push(g[0] - center[0], g[1] - center[1], g[2] - center[2]);
      nor.push(...turn(...normal));
      uv.push(t[0] * Math.max(1, Math.round(b.h / 20)), t[1]);
      col.push(...(gray ? [190, 190, 190, 255] : b.color));
    }
    ids.push(b.id);
    ranges.push(face, face + corners.length / 3 - 1);
    face += corners.length / 3;
  }
  return { pos: new Float32Array(pos), nor: new Float32Array(nor), uv: new Float32Array(uv), col: new Uint8Array(col), ids, ranges: new Uint32Array(ranges) };
}

/** The uncompressed buffer: vertex and feature counts, then position, normal, uv0, color, featureId (UInt64) and faceRange. */
function uncompressed(m) {
  const n = m.pos.length / 3;
  const ids = new Uint32Array(m.ids.flatMap((id) => [id, 0]));
  const parts = [new Uint32Array([n, m.ids.length]), m.pos, m.nor, m.uv, m.col, ids, m.ranges];
  return Buffer.concat(parts.map((a) => Buffer.from(a.buffer, a.byteOffset, a.byteLength)));
}

const em = await draco3d.createEncoderModule({});
/** The Draco buffer: positions scaled to about meters by i3s-scale_x and _y, the feature index with i3s-feature-ids. */
function draco(m) {
  const n = m.pos.length / 3;
  const [sx, sy] = [1e-5, 1e-5];
  const builder = new em.MeshBuilder();
  const meta = new em.MetadataBuilder();
  const dm = new em.Mesh();
  const faces = Uint32Array.from({ length: n }, (_, i) => i);
  builder.AddFacesToMesh(dm, n / 3, faces);
  const scaled = Float32Array.from(m.pos, (v, i) => (i % 3 === 0 ? v / sx : i % 3 === 1 ? v / sy : v));
  const position = builder.AddFloatAttribute(dm, em.POSITION, n, 3, scaled);
  builder.AddFloatAttribute(dm, em.NORMAL, n, 3, m.nor);
  builder.AddFloatAttribute(dm, em.TEX_COORD, n, 2, m.uv);
  builder.AddUInt8Attribute(dm, em.COLOR, n, 4, m.col);
  const index = new Uint32Array(n);
  m.ids.forEach((_, f) => index.fill(f, m.ranges[f * 2] * 3, m.ranges[f * 2 + 1] * 3 + 3));
  const feature = builder.AddUInt32Attribute(dm, em.GENERIC, n, 1, index);
  const pm = new em.Metadata();
  meta.AddDoubleEntry(pm, "i3s-scale_x", sx);
  meta.AddDoubleEntry(pm, "i3s-scale_y", sy);
  builder.SetMetadataForAttribute(dm, position, pm);
  const fm = new em.Metadata();
  meta.AddStringEntry(fm, "i3s-attribute-type", "feature-index");
  meta.AddIntEntryArray(fm, "i3s-feature-ids", new Int32Array(m.ids), m.ids.length);
  builder.SetMetadataForAttribute(dm, feature, fm);
  const encoder = new em.Encoder();
  encoder.SetAttributeQuantization(em.POSITION, 16);
  encoder.SetAttributeQuantization(em.NORMAL, 10);
  encoder.SetAttributeQuantization(em.TEX_COORD, 12);
  encoder.SetSpeedOptions(5, 5);
  const out = new em.DracoInt8Array();
  const size = encoder.EncodeMeshToDracoBuffer(dm, out);
  if (size <= 0) throw new Error("Draco encoding failed");
  const bytes = Buffer.alloc(size);
  for (let i = 0; i < size; i++) bytes[i] = out.GetValue(i) & 255;
  [builder, meta, dm, pm, fm, encoder, out].forEach((x) => em.destroy(x));
  return bytes;
}

/** A 64 x 64 RGB PNG of window rows: light frames, blue glass. */
function png() {
  const size = 64;
  const rows = [];
  for (let y = 0; y < size; y++) {
    const row = [0];
    for (let x = 0; x < size; x++) {
      const frame = x % 16 < 3 || y % 16 < 4;
      row.push(...(frame ? [225, 220, 205] : [60 + (y % 16) * 4, 100 + (x % 16) * 3, 160]));
    }
    rows.push(...row);
  }
  const chunk = (type, data) => {
    const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const crc = Buffer.alloc(4);
    crc.writeUInt32BE(crc32(body));
    return Buffer.concat([len, body, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr.set([8, 2, 0, 0, 0], 8);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(Buffer.from(rows))), chunk("IEND", Buffer.alloc(0))]);
}

/** The attribute buffers of `buildings`: OBJECTID (Oid32), name (String, NUL-terminated) and height (Float64, after 4 bytes of padding). */
function attributes(buildings) {
  const n = buildings.length;
  const strings = buildings.map((b) => Buffer.from(b.name + "\0", "utf8"));
  const total = strings.reduce((a, s) => a + s.length, 0);
  return {
    f_0: Buffer.from(new Uint32Array([n, ...buildings.map((b) => b.id)]).buffer),
    f_1: Buffer.concat([Buffer.from(new Uint32Array([n, total, ...strings.map((s) => s.length)]).buffer), ...strings]),
    f_2: Buffer.concat([Buffer.from(new Uint32Array([n, 0]).buffer), Buffer.from(new Float64Array(buildings.map((b) => b.h)).buffer)]),
  };
}

/** An oriented box around `buildings` in the frame at their middle: center in degrees and meters, half sizes, the frame's quaternion in ECEF. */
function obb(buildings) {
  let [x0, x1, y0, y1, h] = [Infinity, -Infinity, Infinity, -Infinity, 0];
  for (const b of buildings) {
    [x0, x1] = [Math.min(x0, b.e - b.w / 2), Math.max(x1, b.e + b.w / 2)];
    [y0, y1] = [Math.min(y0, b.n - b.d / 2), Math.max(y1, b.n + b.d / 2)];
    h = Math.max(h, b.h);
  }
  const c = toCartographic(ecef((x0 + x1) / 2, (y0 + y1) / 2, h / 2));
  const m = eastNorthUp(toCartesian(c[0], c[1], c[2]));
  const [m00, m10, m20, m01, m11, m21, m02, m12, m22] = [m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]];
  const w = Math.sqrt(Math.max(0, 1 + m00 + m11 + m22)) / 2;
  const quaternion = [(m21 - m12) / (4 * w), (m02 - m20) / (4 * w), (m10 - m01) / (4 * w), w];
  return { center: c, halfSize: [(x1 - x0) / 2 + 1, (y1 - y0) / 2 + 1, h / 2 + 1], quaternion };
}

const BLOCKS = [0, 1, 2, 3].map((k) => BUILDINGS.filter((b) => b.block === k));
const TEXTURED = new Set([1, 3]);
// The root's mesh: each block as one gray box around its buildings, the block's first building as its feature.
const ROOT_BOXES = BLOCKS.map((bs) => {
  const xs = bs.flatMap((b) => [b.e - b.w / 2, b.e + b.w / 2]);
  const ys = bs.flatMap((b) => [b.n - b.d / 2, b.n + b.d / 2]);
  const [e0, e1, n0, n1] = [Math.min(...xs), Math.max(...xs), Math.min(...ys), Math.max(...ys)];
  return { ...bs[0], e: (e0 + e1) / 2, n: (n0 + n1) / 2, w: e1 - e0, d: n1 - n0, h: Math.max(...bs.map((b) => b.h)) };
});

await rm(DIR, { recursive: true, force: true });
const nodes = [];
const contents = [[ROOT_BOXES, true], ...BLOCKS.map((bs) => [bs, false])];
for (const [index, [buildings, gray]] of contents.entries()) {
  const box = obb(buildings);
  const m = mesh(buildings, box.center, gray);
  const dir = path.join(DIR, "nodes", String(index));
  await mkdir(path.join(dir, "geometries"), { recursive: true });
  await writeFile(path.join(dir, "geometries/0"), uncompressed(m));
  await writeFile(path.join(dir, "geometries/1"), draco(m));
  const textured = TEXTURED.has(index);
  if (textured) {
    await mkdir(path.join(dir, "textures"), { recursive: true });
    await writeFile(path.join(dir, "textures/0"), png());
  }
  for (const [key, bytes] of Object.entries(attributes(buildings))) {
    await mkdir(path.join(dir, "attributes", key), { recursive: true });
    await writeFile(path.join(dir, "attributes", key, "0"), bytes);
  }
  nodes.push({
    index,
    ...(index > 0 && { parentIndex: 0 }),
    lodThreshold: index === 0 ? ROOT_THRESHOLD : CHILD_THRESHOLD,
    obb: box,
    ...(index === 0 && { children: [1, 2, 3, 4] }),
    mesh: {
      material: { definition: textured ? 1 : 0, resource: index },
      geometry: { definition: 0, resource: index, vertexCount: m.pos.length / 3, featureCount: m.ids.length },
      attribute: { resource: index },
    },
  });
}
await mkdir(path.join(DIR, "nodepages"), { recursive: true });
await writeFile(path.join(DIR, "nodepages/0"), JSON.stringify({ nodes }));

const sr = { wkid: 4326, latestWkid: 4326 };
const layer = {
  id: 0,
  version: "{6F2E9C4A-1B7D-4C55-9E21-5A0F3B8D7C10}",
  name: "Synthetic buildings",
  href: "./layers/0",
  layerType: "3DObject",
  spatialReference: sr,
  heightModelInfo: { heightModel: "ellipsoidal", vertCRS: "WGS_84", heightUnit: "meter" },
  alias: "Synthetic buildings",
  copyrightText: "mbmap test data",
  capabilities: ["View", "Query"],
  fullExtent: { ...sr, xmin: CENTER[0] - 0.004, xmax: CENTER[0] + 0.004, ymin: CENTER[1] - 0.003, ymax: CENTER[1] + 0.003, zmin: 0, zmax: 150 },
  store: {
    id: "{0B3D6E6A-6C1E-4F44-8F0B-7B2C1D9E5A31}",
    profile: "meshpyramids",
    version: "1.8",
    resourcePattern: ["3dNodeIndexDocument", "Attributes", "SharedResource", "Geometry"],
    rootNode: "./nodes/root",
    extent: [CENTER[0] - 0.004, CENTER[1] - 0.003, CENTER[0] + 0.004, CENTER[1] + 0.003],
    indexCRS: "http://www.opengis.net/def/crs/EPSG/0/4326",
    vertexCRS: "http://www.opengis.net/def/crs/EPSG/0/4326",
    normalReferenceFrame: "earth-centered",
    lodType: "MeshPyramid",
    lodModel: "node-switching",
    defaultGeometrySchema: {
      geometryType: "triangles",
      header: [{ property: "vertexCount", type: "UInt32" }, { property: "featureCount", type: "UInt32" }],
      topology: "PerAttributeArray",
      ordering: ["position", "normal", "uv0", "color"],
      vertexAttributes: {
        position: { valueType: "Float32", valuesPerElement: 3 },
        normal: { valueType: "Float32", valuesPerElement: 3 },
        uv0: { valueType: "Float32", valuesPerElement: 2 },
        color: { valueType: "UInt8", valuesPerElement: 4 },
      },
      featureAttributeOrder: ["id", "faceRange"],
      featureAttributes: { id: { valueType: "UInt64", valuesPerElement: 1 }, faceRange: { valueType: "UInt32", valuesPerElement: 2 } },
    },
  },
  nodePages: { nodesPerPage: 64, lodSelectionMetricType: "maxScreenThresholdSQ" },
  materialDefinitions: [
    { cullFace: "back", pbrMetallicRoughness: { metallicFactor: 0 } },
    { cullFace: "back", pbrMetallicRoughness: { baseColorTexture: { textureSetDefinitionId: 0, texCoord: 0 }, metallicFactor: 0 } },
  ],
  textureSetDefinitions: [{ formats: [{ name: "0", format: "png" }] }],
  geometryDefinitions: [
    {
      geometryBuffers: [
        {
          offset: 8,
          position: { type: "Float32", component: 3 },
          normal: { type: "Float32", component: 3 },
          uv0: { type: "Float32", component: 2 },
          color: { type: "UInt8", component: 4 },
          featureId: { type: "UInt64", component: 1, binding: "per-feature" },
          faceRange: { type: "UInt32", component: 2, binding: "per-feature" },
        },
        { compressedAttributes: { encoding: "draco", attributes: ["position", "normal", "uv0", "color", "feature-index"] } },
      ],
    },
  ],
  fields: [
    { name: "OBJECTID", type: "esriFieldTypeOID", alias: "OBJECTID" },
    { name: "name", type: "esriFieldTypeString", alias: "name" },
    { name: "height", type: "esriFieldTypeDouble", alias: "height" },
  ],
  attributeStorageInfo: [
    { key: "f_0", name: "OBJECTID", header: [{ property: "count", valueType: "UInt32" }], ordering: ["attributeValues"], attributeValues: { valueType: "Oid32", valuesPerElement: 1 } },
    {
      key: "f_1", name: "name",
      header: [{ property: "count", valueType: "UInt32" }, { property: "attributeValuesByteCount", valueType: "UInt32" }],
      ordering: ["attributeByteCounts", "attributeValues"],
      attributeByteCounts: { valueType: "UInt32", valuesPerElement: 1 },
      attributeValues: { valueType: "String", encoding: "UTF-8", valuesPerElement: 1 },
    },
    { key: "f_2", name: "height", header: [{ property: "count", valueType: "UInt32" }], ordering: ["attributeValues"], attributeValues: { valueType: "Float64", valuesPerElement: 1 } },
  ],
};
await writeFile(path.join(DIR, "layer.json"), JSON.stringify(layer, null, 1) + "\n");
console.log(`wrote ${nodes.length} nodes to ${path.relative(ROOT, DIR)}`);
