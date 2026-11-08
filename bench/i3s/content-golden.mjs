// mbmap/3d's I3S node contents (npm/src/i3s/content.ts; Draco by model_worker's wasm) vs @loaders.gl/i3s 4.5.4
// on Esri's sample layers (bench/fixtures/i3s-sf, i3s-frankfurt) and the synthetic one, hostile copies refused.
// Usage: node i3s/content-golden.mjs; writes bench/results/i3s-contents.json.
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { setLoaderOptions } from "@loaders.gl/core";
import { DracoLoader } from "@loaders.gl/draco";
import { parse } from "@loaders.gl/core";
import draco3d from "draco3d";
import { parseI3STileContent } from "../node_modules/@loaders.gl/i3s/dist/lib/parsers/parse-i3s-tile-content.js";
import { parseI3STileAttribute } from "../node_modules/@loaders.gl/i3s/dist/lib/parsers/parse-i3s-attribute.js";
import { getAttributeValueType } from "../node_modules/@loaders.gl/i3s/dist/i3s-attribute-loader.js";
import { draco } from "../../model_worker/js/decode.mjs";
import { cartesian, readI3sAttribute, readI3sGeometry } from "../../npm/src/i3s/content.ts";
import { eastNorthUp } from "../../npm/src/tiles/geo.ts";
import { ROOT } from "../lib/root.mjs";

setLoaderOptions({ worker: false, modules: { draco3d } });
const MODEL_WASM = path.join(ROOT, "_build/wasm-gc/release/build/model_worker/model_worker.wasm");
const { instance } = await WebAssembly.instantiate(await readFile(MODEL_WASM), {});
const decode = draco(instance.exports);

const LAYERS = [
  ["i3s-sf", path.join(ROOT, "bench/fixtures/i3s-sf")],
  ["i3s-frankfurt", path.join(ROOT, "bench/fixtures/i3s-frankfurt")],
  ["synthetic", path.join(ROOT, "bench/npm/pages/i3s/set/layers/0")],
];

const buf = (b) => b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength);
const results = { layers: {}, hostile: [] };
let differ = 0;
let maxMeters = 0;

/** loaders.gl's 1.6-style geometry schema for an uncompressed geometry buffer of a 1.7 definition. */
function schemaOf(def) {
  const names = [["position", "position"], ["normal", "normal"], ["uv0", "uv0"], ["color", "color"], ["uvRegion", "region"]].filter(([k]) => def[k]);
  const a = (x) => ({ valueType: x.type, valuesPerElement: x.component });
  return {
    header: def.offset >= 8 ? [{ property: "vertexCount", type: "UInt32" }, { property: "featureCount", type: "UInt32" }] : [],
    ordering: names.map(([, n]) => n),
    vertexAttributes: Object.fromEntries(names.map(([k, n]) => [n, a(def[k])])),
    featureAttributeOrder: ["id", "faceRange"],
    featureAttributes: { id: a(def.featureId), faceRange: a(def.faceRange) },
  };
}

function same(a, b, what, problems) {
  if (!a && !b) return;
  if (!a || !b || a.length !== b.length) return problems.push(`${what}: lengths ${a?.length} and ${b?.length}`);
  for (let i = 0; i < a.length; i++) if (!Object.is(a[i], b[i])) return problems.push(`${what}[${i}]: ${a[i]} vs ${b[i]}`);
}

/** Every difference between our content of a node's buffer and loaders.gl's. */
async function compare(bytes, layer, node, b) {
  const problems = [];
  const def = layer.geometryDefinitions[node.mesh.geometry.definition].geometryBuffers[b];
  const isDraco = Boolean(def.compressedAttributes);
  const ours = readI3sGeometry(bytes, layer, node, b, decode);
  const theirs = await parseI3STileContent(buf(bytes), { mbs: [...node.obb.center, 1], isDracoGeometry: isDraco }, { store: { defaultGeometrySchema: !isDraco && schemaOf(def) } }, { i3s: {} }, {});
  const a = ours.primitive.attributes;
  const n = ours.count;
  if (theirs.vertexCount !== n) problems.push(`vertex count ${n} vs ${theirs.vertexCount}`);
  // Positions: loaders.gl's ECEF (f64) taken into our frame and rounded must be ours; ours back to ECEF within f32 rounding.
  const origin = cartesian(...ours.center);
  const m = eastNorthUp(origin);
  const enu = new Float32Array(n * 3);
  const p = theirs.attributes.positions.value;
  for (let i = 0; i < n * 3; i += 3) {
    const [dx, dy, dz] = [p[i] - origin[0], p[i + 1] - origin[1], p[i + 2] - origin[2]];
    enu[i] = m[0] * dx + m[1] * dy + m[2] * dz;
    enu[i + 1] = m[4] * dx + m[5] * dy + m[6] * dz;
    enu[i + 2] = m[8] * dx + m[9] * dy + m[10] * dz;
    const [e, nn, u] = [a.POSITION.data[i], a.POSITION.data[i + 1], a.POSITION.data[i + 2]];
    const back = [0, 1, 2].map((k) => origin[k] + m[k] * e + m[4 + k] * nn + m[8 + k] * u);
    maxMeters = Math.max(maxMeters, Math.hypot(back[0] - p[i], back[1] - p[i + 1], back[2] - p[i + 2]));
  }
  same(a.POSITION.data, enu, "positions", problems);
  const normals = theirs.attributes.normals?.value;
  if (normals && layer.store?.normalReferenceFrame !== "east-north-up") {
    const turned = new Float32Array(normals.length);
    for (let i = 0; i < normals.length; i += 3) for (let k = 0; k < 3; k++) turned[i + k] = m[k * 4] * normals[i] + m[k * 4 + 1] * normals[i + 1] + m[k * 4 + 2] * normals[i + 2];
    same(a.NORMAL?.data, turned, "normals", problems);
  } else {
    same(a.NORMAL?.data, normals, "normals", problems);
  }
  same(a.TEXCOORD_0?.data, theirs.attributes.texCoords?.value, "uv0", problems);
  same(a.COLOR_0?.data, theirs.attributes.colors?.value, "colors", problems);
  same(a._UV_REGION?.data, theirs.attributes.uvRegions?.value, "uv regions", problems);
  same(ours.primitive.indices, theirs.indices, "indices", problems);
  // Feature ids per vertex: loaders.gl's are the ids themselves (Uint32 when uncompressed, Float32 from Draco).
  const index = a._BATCHID.data;
  const ids = ours.featureIds;
  const perVertex = Array.from(index, (k) => (isDraco ? Math.fround(ids[k]) : ids[k] % 2 ** 32));
  same(perVertex, Array.from(theirs.featureIds).slice(0, n), "feature ids per vertex", problems);
  if (isDraco) {
    // The raw feature indices and ids, from loaders.gl's DracoLoader with I3S's attribute names.
    const mesh = await parse(buf(bytes), DracoLoader, { draco: { attributeNameEntry: "i3s-attribute-type" } });
    const fi = mesh.attributes["feature-index"];
    if (fi) {
      same(Array.from(index), Array.from(fi.value, Number), "feature indices", problems);
      const meta = Object.values(mesh.loaderData.attributes).find((x) => x.name === "feature-index")?.metadata;
      same(Array.from(ids), Array.from(meta?.["i3s-feature-ids"]?.intArray ?? []), "feature ids", problems);
    }
  }
  return { problems, n, features: ids.length, draco: isDraco };
}

for (const [name, dir] of LAYERS) {
  if (!existsSync(path.join(dir, "layer.json"))) {
    console.warn(`${name}: no fixture (npm run fixtures, or node i3s/synthetic.mjs); skipped`);
    continue;
  }
  const layer = JSON.parse(await readFile(path.join(dir, "layer.json"), "utf8"));
  const pages = [];
  for (let p = 0; p < 1024; p++) if (existsSync(path.join(dir, `nodepages/${p}`))) pages.push(...JSON.parse(await readFile(path.join(dir, `nodepages/${p}`), "utf8")).nodes);
  const row = { buffers: 0, vertices: 0, features: 0, attributes: 0, values: 0, differ: 0, problems: [] };
  for (const node of pages) {
    const r = node.mesh?.geometry?.resource;
    if (r === undefined) continue;
    for (const b of [0, 1]) {
      const file = path.join(dir, `nodes/${r}/geometries/${b}`);
      if (!existsSync(file)) continue;
      const { problems, n, features } = await compare(new Uint8Array(await readFile(file)), layer, node, b);
      row.buffers++;
      row.vertices += n;
      row.features += features;
      if (problems.length) {
        row.differ++;
        row.problems.push(`node ${node.index} buffer ${b}: ${problems.slice(0, 3).join("; ")}`);
      }
    }
    for (const info of layer.attributeStorageInfo ?? []) {
      const file = path.join(dir, `nodes/${node.mesh.attribute?.resource}/attributes/${info.key}/0`);
      if (!existsSync(file)) continue;
      const bytes = new Uint8Array(await readFile(file));
      const ours = Array.from(readI3sAttribute(bytes, info));
      const theirs = Array.from(parseI3STileAttribute(buf(bytes), { attributeName: info.name, attributeType: getAttributeValueType(info) })[info.name], (v) => (typeof v === "string" && v.endsWith("\0") ? v.slice(0, -1) : v));
      const problems = [];
      same(ours, theirs, `${info.name}`, problems);
      row.attributes++;
      row.values += ours.length;
      if (problems.length) {
        row.differ++;
        row.problems.push(`node ${node.index}: ${problems[0]}`);
      }
    }
  }
  differ += row.differ;
  results.layers[name] = row;
  console.log(`${name}: ${row.buffers} geometry buffers (${row.vertices} vertices, ${row.features} features), ${row.attributes} attribute buffers (${row.values} values), ${row.differ} differ`);
  for (const p of row.problems.slice(0, 10)) console.log(`  ${p}`);
}

// Hostile copies of the synthetic layer's first child: each must be refused.
const SYN = path.join(ROOT, "bench/npm/pages/i3s/set/layers/0");
if (existsSync(path.join(SYN, "layer.json"))) {
  const layer = JSON.parse(await readFile(path.join(SYN, "layer.json"), "utf8"));
  const node = JSON.parse(await readFile(path.join(SYN, "nodepages/0"), "utf8")).nodes[1];
  const plain = new Uint8Array(await readFile(path.join(SYN, "nodes/1/geometries/0")));
  const packed = new Uint8Array(await readFile(path.join(SYN, "nodes/1/geometries/1")));
  const name = new Uint8Array(await readFile(path.join(SYN, "nodes/1/attributes/f_1/0")));
  const edit = (bytes, f) => {
    const c = bytes.slice();
    f(new DataView(c.buffer), c);
    return c;
  };
  const geometry = [
    ["empty", new Uint8Array(0), 0],
    ["header only", plain.slice(0, 8), 0],
    ["cut in the feature table", plain.slice(0, plain.length - 4), 0],
    ["vertex count past the buffer", edit(plain, (v) => v.setUint32(0, 3 * 1000, true)), 0],
    ["huge vertex count", edit(plain, (v) => v.setUint32(0, 0xfffffff0 - 1, true)), 0],
    ["vertex count not of triangles", edit(plain, (v) => v.setUint32(0, v.getUint32(0, true) - 1, true)), 0],
    ["huge feature count", edit(plain, (v) => v.setUint32(4, 0xffffffff, true)), 0],
    ["face range past the vertices", edit(plain, (v, c) => v.setUint32(c.length - 4, 1e6, true)), 0],
    ["face range backwards", edit(plain, (v, c) => v.setUint32(c.length - 8, 1e5, true)), 0],
    ["Draco cut", packed.slice(0, packed.length >> 1), 1],
    ["Draco garbage", edit(packed, (_, c) => c.fill(0x5a, 16)), 1],
    ["not Draco", plain, 1],
  ];
  for (const [what, bytes, b] of geometry) {
    let refused = false;
    try {
      readI3sGeometry(bytes, layer, node, b, decode);
    } catch {
      refused = true;
    }
    results.hostile.push({ what, refused });
  }
  const wrongCrs = { ...layer, spatialReference: { wkid: 3857, latestWkid: 3857 } };
  const others = [
    ["Web Mercator layer", () => readI3sGeometry(plain, wrongCrs, node, 0, decode)],
    ["undefined buffer", () => readI3sGeometry(plain, layer, node, 5, decode)],
    ["string count past the buffer", () => readI3sAttribute(edit(name, (v) => v.setUint32(0, 1e6, true)), layer.attributeStorageInfo[1])],
    ["string bytes past the buffer", () => readI3sAttribute(edit(name, (v) => v.setUint32(8, 1e6, true)), layer.attributeStorageInfo[1])],
    ["values past the buffer", () => readI3sAttribute(name.slice(0, 6), layer.attributeStorageInfo[2])],
    ["unknown value type", () => readI3sAttribute(name, { ...layer.attributeStorageInfo[2], attributeValues: { valueType: "Float128" } })],
  ];
  for (const [what, f] of others) {
    let refused = false;
    try {
      f();
    } catch {
      refused = true;
    }
    results.hostile.push({ what, refused });
  }
}
const accepted = results.hostile.filter((h) => !h.refused);
console.log(`hostile: ${results.hostile.length - accepted.length} of ${results.hostile.length} refused${accepted.length ? ` (accepted: ${accepted.map((h) => h.what).join(", ")})` : ""}`);
console.log(`positions back to ECEF: at most ${maxMeters.toExponential(2)} m from loaders.gl's (f32 rounding of east, north, up meters)`);
results.maxPositionMeters = maxMeters;
results.differ = differ;
await mkdir(path.join(ROOT, "bench/results"), { recursive: true });
await writeFile(path.join(ROOT, "bench/results/i3s-contents.json"), JSON.stringify({ date: new Date().toISOString(), node: process.version, ...results }, null, 2) + "\n");
if (differ || accepted.length) process.exitCode = 1;
