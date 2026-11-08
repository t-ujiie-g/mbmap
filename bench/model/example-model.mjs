// Writes the showcase's model (examples/shared/tower.glb): a clock tower 60 m tall, its base at the
// origin, meshopt-compressed. Usage: node model/example-model.mjs
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
const acc = (type, array) => doc.createAccessor().setType(type).setArray(array).setBuffer(buf);

/** A box from `lo` to `hi` (x, y up, z), each face with its own normal. */
function box(lo, hi) {
  const pos = [];
  const nor = [];
  const idx = [];
  for (let axis = 0; axis < 3; axis++) {
    for (const side of [-1, 1]) {
      const [u, v] = [(axis + 1) % 3, (axis + 2) % 3];
      const base = pos.length / 3;
      for (const [a, b] of side > 0 ? [[0, 0], [1, 0], [1, 1], [0, 1]] : [[0, 0], [0, 1], [1, 1], [1, 0]]) {
        const p = [];
        p[axis] = side > 0 ? hi[axis] : lo[axis];
        p[u] = a ? hi[u] : lo[u];
        p[v] = b ? hi[v] : lo[v];
        pos.push(...p);
        nor.push(...[0, 1, 2].map((k) => (k === axis ? side : 0)));
      }
      idx.push(base, base + 1, base + 2, base, base + 2, base + 3);
    }
  }
  return { pos, nor, idx };
}

/** A four-sided pyramid roof over `lo`..`hi` (x, z) from `y0` up to `top`. */
function roof([x0, z0], [x1, z1], y0, top) {
  const apex = [(x0 + x1) / 2, top, (z0 + z1) / 2];
  const corners = [[x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1]];
  const pos = [];
  const nor = [];
  const idx = [];
  for (let i = 0; i < 4; i++) {
    const [a, b] = [corners[i], corners[(i + 1) % 4]];
    const e1 = b.map((v, k) => v - a[k]);
    const e2 = apex.map((v, k) => v - a[k]);
    const n = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
    const l = Math.hypot(...n);
    const base = pos.length / 3;
    pos.push(...a, ...b, ...apex);
    for (let k = 0; k < 3; k++) nor.push(...n.map((v) => v / l));
    idx.push(base, base + 2, base + 1);
  }
  return { pos, nor, idx };
}

const parts = [
  [box([-15, 0, -15], [15, 8, 15]), [0.72, 0.7, 0.66, 1]],
  [box([-6, 8, -6], [6, 48, 6]), [0.66, 0.32, 0.22, 1]],
  [box([-7, 40, -7], [7, 46, 7]), [0.95, 0.93, 0.85, 1]],
  [roof([-7, -7], [7, 7], 48, 62), [0.25, 0.45, 0.4, 1]],
];
const mesh = doc.createMesh("tower");
for (const [{ pos, nor, idx }, color] of parts) {
  mesh.addPrimitive(doc.createPrimitive()
    .setAttribute("POSITION", acc("VEC3", new Float32Array(pos)))
    .setAttribute("NORMAL", acc("VEC3", new Float32Array(nor)))
    .setIndices(acc("SCALAR", new Uint16Array(idx)))
    .setMaterial(doc.createMaterial().setBaseColorFactor(color)));
}
doc.createScene().addChild(doc.createNode("tower").setMesh(mesh));
await doc.transform(quantize());
doc.createExtension(EXTMeshoptCompression).setRequired(true).setEncoderOptions({ method: "filter" });
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ "meshopt.encoder": MeshoptEncoder });
await writeFile(path.join(ROOT, "examples/shared/tower.glb"), await io.writeBinary(doc));
