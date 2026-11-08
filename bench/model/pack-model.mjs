// Writes the pack test's model (bench/npm/pages/model/box.glb): a red box 40 m wide and tall, its
// base at the origin, quantized and meshopt-compressed so that loading it goes through 3d.wasm.
// Usage: node model/pack-model.mjs
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { Document, NodeIO } from "@gltf-transform/core";
import { ALL_EXTENSIONS, EXTMeshoptCompression } from "@gltf-transform/extensions";
import { quantize } from "@gltf-transform/functions";
import { MeshoptEncoder } from "meshoptimizer";
import { ROOT } from "../lib/root.mjs";

await MeshoptEncoder.ready;
const doc = new Document();
const buf = doc.createBuffer();
// Each face its own four corners, so each has its normal.
const faces = [[[1, 0, 0]], [[-1, 0, 0]], [[0, 1, 0]], [[0, -1, 0]], [[0, 0, 1]], [[0, 0, -1]]].map(([n]) => n);
const pos = [];
const nor = [];
const idx = [];
for (const n of faces) {
  const axis = n.findIndex((v) => v !== 0);
  const [u, v] = [(axis + 1) % 3, (axis + 2) % 3];
  const base = pos.length / 3;
  for (const [a, b] of [[-1, -1], [1, -1], [1, 1], [-1, 1]]) {
    const p = [0, 0, 0];
    p[axis] = n[axis];
    p[u] = a;
    p[v] = b;
    pos.push(p[0] * 20, p[1] * 20 + 20, p[2] * 20);
    nor.push(...n);
  }
  idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
}
const acc = (type, array) => doc.createAccessor().setType(type).setArray(array).setBuffer(buf);
const prim = doc.createPrimitive()
  .setAttribute("POSITION", acc("VEC3", new Float32Array(pos)))
  .setAttribute("NORMAL", acc("VEC3", new Float32Array(nor)))
  .setIndices(acc("SCALAR", new Uint16Array(idx)))
  .setMaterial(doc.createMaterial("red").setBaseColorFactor([0.9, 0.1, 0.1, 1]).setDoubleSided(true));
doc.createScene().addChild(doc.createNode("box").setMesh(doc.createMesh().addPrimitive(prim)));
await doc.transform(quantize());
doc.createExtension(EXTMeshoptCompression).setRequired(true).setEncoderOptions({ method: "filter" });
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ "meshopt.encoder": MeshoptEncoder });
await writeFile(path.join(ROOT, "bench/npm/pages/model/box.glb"), await io.writeBinary(doc));
