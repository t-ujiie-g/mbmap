// mbmap/3d's glTF reading (loadModel in Chromium: npm/src/model/gltf.ts and meshopt in 3d.wasm) vs
// @loaders.gl/gltf 4.5.4 (attributes, indices, materials, KHR_texture_transform) and gltf-transform
// 4.5.1's world matrices, on models written by gltf-transform: plain, quantized (KHR_mesh_quantization),
// meshopt-compressed (EXT_ and KHR_meshopt_compression, both encoder methods), sparse, interleaved,
// several node levels, WebP and PNG textures, a .gltf with its .bin and image beside it, and hostile
// files. Needs `npm --prefix npm run build`. Writes bench/results/model-golden.json.
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { Document, NodeIO } from "@gltf-transform/core";
import { ALL_EXTENSIONS, EXTMeshoptCompression, KHRMaterialsUnlit, KHRTextureTransform, EXTTextureWebP } from "@gltf-transform/extensions";
import { quantize, reorder } from "@gltf-transform/functions";
import { parse } from "@loaders.gl/core";
import { GLTFLoader, postProcessGLTF } from "@loaders.gl/gltf";
import { MeshoptDecoder, MeshoptEncoder } from "meshoptimizer";
import { encodePng } from "../lib/png.mjs";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";

const OUT = path.join(ROOT, "bench/dist/models");
await mkdir(OUT, { recursive: true });
await MeshoptEncoder.ready;
await MeshoptDecoder.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ "meshopt.encoder": MeshoptEncoder, "meshopt.decoder": MeshoptDecoder });

// Mulberry32: the same models on every run.
function rng(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** A `n` x `n` grid bent into a hill: positions, normals, UVs, colors and triangle indices. */
function grid(n, rand) {
  const pos = [];
  const nor = [];
  const uv = [];
  const col = [];
  for (let j = 0; j <= n; j++) {
    for (let i = 0; i <= n; i++) {
      const [x, z] = [i / n - 0.5, j / n - 0.5];
      const y = Math.cos(x * 3) * Math.cos(z * 3) * 0.3 + rand() * 0.01;
      pos.push(x * 20, y * 20, z * 20);
      const nx = -Math.sin(x * 3) * Math.cos(z * 3) * 0.9;
      const nz = -Math.cos(x * 3) * Math.sin(z * 3) * 0.9;
      const l = Math.hypot(nx, 1, nz);
      nor.push(nx / l, 1 / l, nz / l);
      uv.push(i / n, j / n);
      col.push(Math.round(255 * i / n), Math.round(255 * j / n), 128, 255);
    }
  }
  const idx = [];
  for (let j = 0; j < n; j++) {
    for (let i = 0; i < n; i++) {
      const a = j * (n + 1) + i;
      idx.push(a, a + n + 1, a + 1, a + 1, a + n + 1, a + n + 2);
    }
  }
  return { pos: new Float32Array(pos), nor: new Float32Array(nor), uv: new Float32Array(uv), col: new Uint8Array(col), idx };
}

/** The scene the models share: a hill, a box with vertex colors under two levels of nodes, a sparse triangle. */
function scene({ webp, png, transform = false, unlit = false, n = 24 }) {
  const doc = new Document();
  const buf = doc.createBuffer();
  const rand = rng(n);
  const g = grid(n, rand);
  const acc = (type, array, normalized = false) => doc.createAccessor().setType(type).setArray(array).setNormalized(normalized).setBuffer(buf);
  const image = doc.createTexture("hill").setImage(webp ?? png).setMimeType(webp ? "image/webp" : "image/png");
  if (webp) doc.createExtension(EXTTextureWebP).setRequired(true);
  const hillMaterial = doc.createMaterial("hill").setBaseColorTexture(image).setBaseColorFactor([1, 0.9, 0.8, 1]);
  if (transform) {
    const ext = doc.createExtension(KHRTextureTransform);
    hillMaterial.getBaseColorTextureInfo().setExtension("KHR_texture_transform", ext.createTransform().setOffset([0.25, 0.5]).setRotation(0.4).setScale([2, 3]));
  }
  if (unlit) hillMaterial.setExtension("KHR_materials_unlit", doc.createExtension(KHRMaterialsUnlit).createUnlit());
  const hill = doc.createPrimitive()
    .setAttribute("POSITION", acc("VEC3", g.pos))
    .setAttribute("NORMAL", acc("VEC3", g.nor))
    .setAttribute("TEXCOORD_0", acc("VEC2", g.uv))
    .setAttribute("COLOR_0", acc("VEC4", g.col, true))
    .setIndices(acc("SCALAR", (g.pos.length / 3 > 65535 ? Uint32Array : Uint16Array).from(g.idx)))
    .setMaterial(hillMaterial);
  const boxPos = new Float32Array([-1, -1, -1, 1, -1, -1, 1, 1, -1, -1, 1, -1, -1, -1, 1, 1, -1, 1, 1, 1, 1, -1, 1, 1]);
  const boxIdx = new Uint8Array([0, 2, 1, 0, 3, 2, 4, 5, 6, 4, 6, 7, 0, 1, 5, 0, 5, 4, 3, 7, 6, 3, 6, 2, 1, 2, 6, 1, 6, 5, 0, 4, 7, 0, 7, 3]);
  const box = doc.createPrimitive()
    .setAttribute("POSITION", acc("VEC3", boxPos))
    .setAttribute("COLOR_0", acc("VEC3", new Float32Array(boxPos.map((v) => (v + 1) / 2))))
    .setIndices(acc("SCALAR", boxIdx))
    .setMaterial(doc.createMaterial("box").setBaseColorFactor([0.8, 0.3, 0.2, 0.7]).setAlphaMode("BLEND").setDoubleSided(true));
  const sparse = acc("VEC3", new Float32Array([0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 2, 0, 0])).setSparse(true);
  const tri = doc.createPrimitive().setAttribute("POSITION", sparse).setMode(4).setMaterial(doc.createMaterial("mask").setAlphaMode("MASK").setAlphaCutoff(0.3));
  const hillNode = doc.createNode("hill").setMesh(doc.createMesh("hill").addPrimitive(hill));
  const boxNode = doc.createNode("box").setMesh(doc.createMesh("box").addPrimitive(box)).setTranslation([3, 4, 5]).setRotation([0, 0.3826834, 0, 0.9238795]);
  const mid = doc.createNode("mid").addChild(boxNode).setScale([2, 0.5, 2]).setTranslation([-4, 0, 0]);
  const triNode = doc.createNode("tri").setMesh(doc.createMesh("tri").addPrimitive(tri)).setMatrix([1, 0, 0, 0, 0, 0, -1, 0, 0, 1, 0, 0, 7, 1, -2, 1]);
  doc.createScene().addChild(hillNode).addChild(mid).addChild(triNode);
  return doc;
}

/** A small PNG and, from Chromium, the same picture as WebP. */
const pixels = new Uint8Array(16 * 16 * 4).map((_, i) => [(i >> 2) % 16 * 16, (i >> 6) * 16, 200, 255][i & 3]);
const png = encodePng(16, 16, pixels, { alpha: true });

const { server, origin } = await serve();
const browser = await chromium.launch();
const results = [];
let failed = 0;
try {
  const page = await browser.newPage();
  page.on("pageerror", (e) => console.log("pageerror", e.message));
  await page.goto(`${origin}/bench/model/page.html`);
  await page.waitForFunction(() => window.__ready, null, { timeout: 30000 });
  const webp = Uint8Array.from(await page.evaluate((png) => window.__webp(png), [...png]));

  // Each model: its file name and bytes (a .gltf also writes its .bin and image beside it).
  const models = {};
  const glb = async (name, doc) => (models[name] = await io.writeBinary(doc));
  await glb("plain.glb", scene({ png }));
  await glb("webp-transform-unlit.glb", scene({ webp, transform: true, unlit: true }));
  const big = scene({ png, n: 300 });
  await glb("large.glb", big);
  const q = scene({ png });
  await q.transform(quantize());
  await glb("quantized.glb", q);
  for (const method of ["quantize", "filter"]) {
    const doc = scene({ webp, transform: true, n: 200 });
    await doc.transform(reorder({ encoder: MeshoptEncoder }), quantize());
    doc.createExtension(EXTMeshoptCompression).setRequired(true).setEncoderOptions({ method });
    await glb(`meshopt-${method}.glb`, doc);
  }
  // KHR_meshopt_compression: the same file with the extension's ratified name (as long as EXT_'s).
  const khr = Buffer.from(models["meshopt-filter.glb"]).toString("latin1").replaceAll("EXT_meshopt_compression", "KHR_meshopt_compression");
  models["meshopt-khr.glb"] = Uint8Array.from(Buffer.from(khr, "latin1"));
  {
    const doc = scene({ png, transform: true });
    const json = await io.writeJSON(doc, { basename: "separate" });
    models["separate.gltf"] = new TextEncoder().encode(JSON.stringify(json.json));
    for (const [name, bytes] of Object.entries(json.resources)) await writeFile(path.join(OUT, name), bytes);
  }
  for (const [name, bytes] of Object.entries(models)) await writeFile(path.join(OUT, name), bytes);

  for (const [name, bytes] of Object.entries(models)) {
    const ours = await page.evaluate((url) => window.__load(url), `/bench/dist/models/${name}`);
    if (ours.error) {
      failed++;
      results.push({ model: name, ok: false, error: ours.error });
      continue;
    }
    const theirs = await reference(name, bytes);
    const differences = compare(ours, theirs);
    if (differences.length) failed++;
    results.push({ model: name, ok: differences.length === 0, primitives: ours.primitives.length, vertices: ours.primitives.reduce((n, p) => n + p.attributes.POSITION.values.length / p.attributes.POSITION.size, 0), images: ours.images, differences: differences.slice(0, 5) });
  }

  // Hostile files: each must be refused with an error, never hang or crash the worker.
  const plain = models["plain.glb"];
  const hostile = {
    "truncated.glb": plain.subarray(0, plain.length >> 1),
    "bad-chunk.glb": (() => { const b = plain.slice(); new DataView(b.buffer).setUint32(12, 0x7fffffff, true); return b; })(),
    "not-json.gltf": new TextEncoder().encode("{ nope"),
    "glTF-1.gltf": new TextEncoder().encode(JSON.stringify({ asset: { version: "1.0" } })),
    "unknown-required.gltf": new TextEncoder().encode(JSON.stringify({ asset: { version: "2.0" }, extensionsRequired: ["EXT_mesh_gpu_instancing"] })),
    "cycle.gltf": new TextEncoder().encode(JSON.stringify({ asset: { version: "2.0" }, scenes: [{ nodes: [0] }], nodes: [{ children: [1] }, { children: [0] }] })),
    "past-view.gltf": new TextEncoder().encode(JSON.stringify({
      asset: { version: "2.0" }, buffers: [{ byteLength: 12, uri: "data:application/octet-stream;base64,AAAAAAAAAAAAAAAA" }],
      bufferViews: [{ buffer: 0, byteLength: 12 }], accessors: [{ bufferView: 0, componentType: 5126, type: "VEC3", count: 100 }],
      meshes: [{ primitives: [{ attributes: { POSITION: 0 } }] }], nodes: [{ mesh: 0 }], scenes: [{ nodes: [0] }],
    })),
    "bad-meshopt.glb": (() => {
      // Each compressed stream's header byte made one no decoder accepts.
      const b = models["meshopt-filter.glb"].slice();
      const v = new DataView(b.buffer);
      const jsonLength = v.getUint32(12, true);
      const json = JSON.parse(new TextDecoder().decode(b.subarray(20, 20 + jsonLength)));
      const bin = 20 + jsonLength + 8;
      for (const view of json.bufferViews) {
        const ext = view.extensions?.EXT_meshopt_compression;
        if (ext) b[bin + (ext.byteOffset ?? 0)] = 0xff;
      }
      return b;
    })(),
  };
  for (const [name, bytes] of Object.entries(hostile)) {
    await writeFile(path.join(OUT, name), bytes);
    const ours = await page.evaluate((url) => window.__load(url), `/bench/dist/models/${name}`);
    const ok = typeof ours.error === "string";
    if (!ok) failed++;
    results.push({ model: name, hostile: true, ok, error: ours.error });
  }
} finally {
  await browser.close();
  server.close();
}

/** loaders.gl's attributes, indices and materials and gltf-transform's world matrices, in mbmap's order. */
async function reference(name, bytes) {
  bytes = webpOptional(bytes);
  const loaded = name.endsWith(".gltf")
    ? await parse(bytes, GLTFLoader, { baseUri: `file://${OUT}/`, gltf: { loadImages: false }, fetch: async (url) => new Response(await (await import("node:fs/promises")).readFile(new URL(url))) })
    : await parse(bytes, GLTFLoader, { gltf: { loadImages: false } });
  const g = postProcessGLTF(loaded);
  // gltf-transform 4.5.1 knows meshopt only by its EXT_ name.
  const ext = Uint8Array.from(Buffer.from(Buffer.from(bytes).toString("latin1").replaceAll("KHR_meshopt_compression", "EXT_meshopt_compression"), "latin1"));
  const doc = name.endsWith(".gltf") ? await io.read(path.join(OUT, name)) : await io.readBinary(ext);
  const docNodes = doc.getRoot().listNodes();
  const primitives = [];
  const visit = (node) => {
    const index = g.nodes.indexOf(node);
    if (node.mesh) {
      for (const p of node.mesh.primitives) {
        const attributes = {};
        for (const [k, a] of Object.entries(p.attributes)) attributes[k] = { values: [...a.value], size: a.components ?? { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4 }[a.type], type: a.componentType, normalized: a.normalized === true };
        primitives.push({ attributes, indices: p.indices ? [...p.indices.value] : null, mode: p.mode ?? 4, matrix: [...docNodes[index].getWorldMatrix()] });
      }
    }
    for (const c of node.children ?? []) visit(c);
  };
  for (const n of (g.scene ?? g.scenes[0]).nodes) visit(n);
  const materials = (g.materials ?? []).map((m) => {
    const pbr = m.pbrMetallicRoughness ?? {};
    return { texCoord: pbr.baseColorTexture?.texCoord ?? 0, color: pbr.baseColorFactor ?? [1, 1, 1, 1], alphaMode: m.alphaMode ?? "OPAQUE", alphaCutoff: m.alphaCutoff ?? 0.5, doubleSided: m.doubleSided === true, unlit: m.unlit === true || Boolean(m.extensions?.KHR_materials_unlit) };
  });
  return { primitives, materials };
}

/**
 * `bytes` with EXT_texture_webp no longer required: loaders.gl refuses it outside a browser, though
 * it reads no images here.
 */
function webpOptional(bytes) {
  const glb = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength).getUint32(0, true) === 0x46546c67;
  const jsonLength = glb ? new DataView(bytes.buffer, bytes.byteOffset).getUint32(12, true) : bytes.length;
  const json = JSON.parse(new TextDecoder().decode(glb ? bytes.subarray(20, 20 + jsonLength) : bytes));
  if (!json.extensionsRequired?.includes("EXT_texture_webp")) return bytes;
  json.extensionsRequired = json.extensionsRequired.filter((e) => e !== "EXT_texture_webp");
  let text = new TextEncoder().encode(JSON.stringify(json));
  if (!glb) return text;
  const padded = new Uint8Array((text.length + 3) & ~3).fill(0x20);
  padded.set(text);
  const rest = bytes.subarray(20 + jsonLength);
  const out = new Uint8Array(20 + padded.length + rest.length);
  out.set(bytes.subarray(0, 12));
  const v = new DataView(out.buffer);
  v.setUint32(8, out.length, true);
  v.setUint32(12, padded.length, true);
  v.setUint32(16, 0x4e4f534a, true);
  out.set(padded, 20);
  out.set(rest, 20 + padded.length);
  return out;
}

/** Where `ours` and `theirs` differ: values exactly, matrices within 1e-9 relative; UVs through ours's texture transform. */
function compare(ours, theirs) {
  const out = [];
  if (ours.primitives.length !== theirs.primitives.length) return [`primitives ${ours.primitives.length} vs ${theirs.primitives.length}`];
  ours.primitives.forEach((p, i) => {
    const q = theirs.primitives[i];
    const material = ours.materials[p.material];
    for (const [name, a] of Object.entries(p.attributes)) {
      const b = q.attributes[name];
      if (!b) { out.push(`${i} ${name} missing in loaders.gl`); continue; }
      const values = a.values;
      if (a.size !== b.size || a.type !== b.type || a.normalized !== b.normalized) out.push(`${i} ${name} layout ${[a.size, a.type, a.normalized]} vs ${[b.size, b.type, b.normalized]}`);
      if (values.length !== b.values.length || values.some((v, k) => !Object.is(v, b.values[k]))) out.push(`${i} ${name} values`);
    }
    // loaders.gl writes the transformed coordinates (from the stored values) as a new TEXCOORD set.
    const tex = material?.texture;
    const transformed = tex?.matrix && q.attributes[`TEXCOORD_${theirs.materials[p.material].texCoord}`];
    if (tex?.matrix) {
      const raw = p.attributes[`TEXCOORD_${tex.texCoord}`].values;
      const m = tex.matrix;
      const mine = raw.map((_, k) => (k & 1 ? m[1] * raw[k - 1] + m[4] * raw[k] + m[7] : m[0] * raw[k] + m[3] * raw[k + 1] + m[6]));
      if (!transformed || mine.length !== transformed.values.length || mine.some((v, k) => Math.abs(v - transformed.values[k]) > 1e-5 * Math.max(1, Math.abs(v)))) out.push(`${i} texture transform`);
    }
    if (Object.keys(q.attributes).some((k) => !p.attributes[k] && q.attributes[k] !== transformed)) out.push(`${i} attributes ${Object.keys(q.attributes)}`);
    if (JSON.stringify(p.indices) !== JSON.stringify(q.indices)) out.push(`${i} indices`);
    if (p.mode !== q.mode) out.push(`${i} mode`);
    if (p.matrix.some((v, k) => Math.abs(v - q.matrix[k]) > 1e-9 * Math.max(1, Math.abs(v)))) out.push(`${i} matrix ${p.matrix} vs ${q.matrix}`);
  });
  theirs.materials.forEach((m, i) => {
    const a = ours.materials[i];
    const same = a && a.alphaMode === m.alphaMode && a.alphaCutoff === m.alphaCutoff && a.doubleSided === m.doubleSided && a.unlit === m.unlit && a.color.every((v, k) => v === m.color[k]);
    if (!same) out.push(`material ${i} ${JSON.stringify(a)} vs ${JSON.stringify(m)}`);
  });
  return out;
}

await writeFile(path.join(ROOT, "bench/results/model-golden.json"), JSON.stringify({ env: { loaders: "@loaders.gl/gltf 4.5.4", gltfTransform: "4.5.1", meshoptimizer: "1.3.0", browser: "chromium" }, results }, null, 2) + "\n");
for (const r of results) console.log(JSON.stringify(r));
console.log(`model golden: ${results.length - failed} of ${results.length} ok`);
if (failed) process.exit(1);
