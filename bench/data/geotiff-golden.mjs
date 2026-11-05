// mbmap/data's readRaster (geotiff.wasm with data_worker/js/geotiff.mjs) vs geotiff 3.0.5's
// readRasters on the Mt Fuji DEM and GSI map tiles (国土地理院) written as TIFFs of every layout
// this reads, from bytes and over HTTP range requests. Usage: node data/geotiff-golden.mjs.
import { readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import path from "node:path";
import { fromArrayBuffer, fromUrl } from "geotiff";
import { dataImports, dataReader, rasterSource } from "../../data_worker/js/read.mjs";
import { decodePng } from "../lib/png.mjs";
import { ROOT } from "../lib/root.mjs";
import { byteRange } from "../lib/serve.mjs";
import { tiffFile } from "./tiff-write.mjs";

const wasmFile = (name) => readFile(path.join(ROOT, `_build/wasm-gc/release/build/${name}/${name}.wasm`));
const imports = dataImports(() => instance.exports.memory);
const { instance } = await WebAssembly.instantiate(await wasmFile("data_worker"), imports);
const geotiffWasm = (await WebAssembly.instantiate(await wasmFile("geotiff_worker"), {})).instance.exports;
const reader = dataReader(instance.exports, imports, { geotiff: async () => geotiffWasm });

// --- Data: the Mt Fuji DEM (GSI's PNG encoding) and a GSI standard map tile ---
const DEM = { z: 12, x: [3625, 3626], y: [1616, 1617], dir: "bench/fixtures/gsi-dem-fuji" };
const SIZE = 256;
const W = SIZE * 2;
const H = SIZE * 2;
const elevation = new Float64Array(W * H);
for (let ty = 0; ty < 2; ty++) {
  for (let tx = 0; tx < 2; tx++) {
    const png = decodePng(await readFile(path.join(ROOT, DEM.dir, `${DEM.z}/${DEM.x[0] + tx}/${DEM.y[0] + ty}.png`)));
    for (let y = 0; y < SIZE; y++) {
      for (let x = 0; x < SIZE; x++) {
        const k = (y * SIZE + x) * 4;
        const v = png.rgba[k] * 65536 + png.rgba[k + 1] * 256 + png.rgba[k + 2];
        elevation[(ty * SIZE + y) * W + tx * SIZE + x] = v === 2 ** 23 ? -9999 : (v < 2 ** 23 ? v : v - 2 ** 24) * 0.01;
      }
    }
  }
}
const stdDir = path.join(ROOT, "bench/fixtures/gsi-std");
const manifest = JSON.parse(await readFile(path.join(ROOT, "bench/fixtures/gsi-std.manifest.json"), "utf8"));
const stdKey = Object.keys(manifest.tiles ?? manifest.files ?? {}).find((k) => k.endsWith(".png") || /^\d+\/\d+\/\d+$/.test(k));
const stdPng = decodePng(await readFile(path.join(stdDir, stdKey.endsWith(".png") ? stdKey : `${stdKey}.png`)));
const rgb = [0, 1, 2].map((c) => Uint8Array.from({ length: stdPng.width * stdPng.height }, (_, i) => stdPng.rgba[i * 4 + c]));

const f32 = (a) => Array.from(Float32Array.from(a));
const half = (a) => Array.from(a, (v) => Math.round(v * 4) / 4).map((v) => Math.max(-2048, Math.min(2048, v)));
const geo = { pixelScale: [0.0001, 0.0001, 0], tiepoint: [0, 0, 0, 138.6, 35.5, 0] };
const keys4326 = [[1024, 2], [1025, 1], [2048, 4326]];
const dem = (over) => ({ width: W, height: H, bits: 32, format: 3, values: [f32(elevation)], geo, keys: keys4326, ...over });

// Files: [label, images, writer options].
const files = [
  ["DEM float32 tiled 64 none", [dem({ tile: [64, 64] })]],
  ["DEM float32 tiled 128 LZW predictor 3", [dem({ tile: [128, 128], compression: 5, predictor: 3 })]],
  ["DEM float32 tiled 64 Deflate predictor 3", [dem({ tile: [64, 64], compression: 8, predictor: 3 })]],
  ["DEM float32 strips of 16 Deflate", [dem({ rows: 16, compression: 8 })]],
  ["DEM float32 strips of 37 LZW", [dem({ rows: 37, compression: 5 })]],
  ["DEM float64 tiled 64 Deflate predictor 3", [dem({ bits: 64, values: [Array.from(elevation)], tile: [64, 64], compression: 8, predictor: 3 })]],
  ["DEM float16 tiled 64 LZW", [dem({ bits: 16, values: [half(elevation)], tile: [64, 64], compression: 5 })]],
  ["DEM int16 tiled 64 LZW predictor 2", [dem({ bits: 16, format: 2, values: [Array.from(elevation, Math.round)], tile: [64, 64], compression: 5, predictor: 2, nodata: "-9999" })]],
  ["DEM uint16 decimeters strips PackBits", [dem({ bits: 16, format: 1, values: [Array.from(elevation, (v) => Math.max(0, Math.round(v * 10)))], rows: 8, compression: 32773 })]],
  ["DEM int32 centimeters tiled Deflate predictor 2", [dem({ bits: 32, format: 2, values: [Array.from(elevation, (v) => Math.round(v * 100))], tile: [64, 64], compression: 8, predictor: 2 })]],
  ["DEM uint32 tiled none", [dem({ bits: 32, format: 1, values: [Array.from(elevation, (v) => Math.max(0, Math.round(v * 100)))], tile: [128, 64] })]],
  ["DEM int8 classes strips LZW", [dem({ bits: 8, format: 2, values: [Array.from(elevation, (v) => Math.max(-128, Math.min(127, Math.round(v / 30) - 64)))], rows: 32, compression: 5 })]],
  ["DEM float32 big-endian tiled LZW", [dem({ tile: [64, 64], compression: 5 })], { little: false }],
  ["DEM float32 big-endian predictor 3", [dem({ tile: [64, 64], compression: 8, predictor: 3 })], { little: false }],
  ["DEM int16 big-endian strips none", [dem({ bits: 16, format: 2, values: [Array.from(elevation, Math.round)], rows: 64 })], { little: false }],
  ["DEM float32 BigTIFF tiled Deflate", [dem({ tile: [64, 64], compression: 8 })], { big: true }],
  ["DEM float32 BigTIFF big-endian", [dem({ tile: [128, 128], compression: 5 })], { big: true, little: false }],
  ["DEM with empty tiles and nodata", [dem({ tile: [64, 64], compression: 8, nodata: "-9999", empty: [0, 5, 63] })]],
  ["DEM with empty tiles, no nodata", [dem({ bits: 16, format: 2, values: [Array.from(elevation, Math.round)], tile: [64, 64], empty: [1, 2, 3] })]],
  ["DEM with ModelTransformation", [dem({ tile: [64, 64], geo: { transform: [0.0001, 0, 0, 138.6, 0, -0.0001, 0, 35.5, 0, 0, 0, 0, 0, 0, 0, 1] } })]],
  ["DEM in EPSG:6677, PixelIsPoint", [dem({ tile: [64, 64], geo: { pixelScale: [10, 10, 0], tiepoint: [0, 0, 0, -60000, -40000, 0] }, keys: [[1024, 1], [1025, 2], [3072, 6677]] })]],
  ["DEM with overviews (COG layout)", [
    dem({ tile: [128, 128], compression: 8, predictor: 3 }),
    { width: W / 2, height: H / 2, bits: 32, format: 3, subfile: 1, tile: [128, 128], compression: 8, predictor: 3, values: [f32(Array.from({ length: (W / 2) * (H / 2) }, (_, i) => elevation[Math.floor(i / (W / 2)) * 2 * W + (i % (W / 2)) * 2]))] },
    { width: W / 4, height: H / 4, bits: 32, format: 3, subfile: 1, tile: [64, 64], compression: 5, values: [f32(Array.from({ length: (W / 4) * (H / 4) }, (_, i) => elevation[Math.floor(i / (W / 4)) * 4 * W + (i % (W / 4)) * 4]))] },
  ], { ifdsFirst: true }],
  ["map RGB tiled LZW predictor 2", [{ width: stdPng.width, height: stdPng.height, bits: 8, format: 1, values: rgb, tile: [64, 64], compression: 5, predictor: 2, geo, keys: keys4326 }]],
  ["map RGB planar 2 strips PackBits", [{ width: stdPng.width, height: stdPng.height, bits: 8, format: 1, values: rgb, planar: 2, rows: 20, compression: 32773, geo, keys: keys4326 }]],
  ["map RGB planar 2 tiled Deflate", [{ width: stdPng.width, height: stdPng.height, bits: 8, format: 1, values: rgb, planar: 2, tile: [128, 128], compression: 8, geo, keys: keys4326 }]],
  ["map red as 1-bit", [{ width: stdPng.width, height: stdPng.height, bits: 1, format: 1, values: [Array.from(rgb[0], (v) => (v > 200 ? 1 : 0))], rows: 30, geo, keys: keys4326 }]],
  ["map red as 4-bit tiled", [{ width: stdPng.width, height: stdPng.height, bits: 4, format: 1, values: [Array.from(rgb[0], (v) => v >> 4)], tile: [64, 64], compression: 5, geo, keys: keys4326 }]],
  ["DEM as 12-bit", [dem({ bits: 12, format: 1, values: [Array.from(elevation, (v) => Math.max(0, Math.min(4095, Math.round(v))))], rows: 13, compression: 8 })]],
];

const variants = (img) => [
  {},
  { window: [10, 20, 300, 260] },
  { window: [-20, -10, 40, 30] },
  { window: [img.width - 30, img.height - 25, img.width + 15, img.height + 9], fillValue: 7 },
  { window: [0, 0, 0, 0] },
  { samples: img.samples > 1 ? [2, 0] : [0] },
  { bbox: [138.61, 35.47, 138.63, 35.49] },
  { window: [5, 5, 205, 155], width: 64, height: 48 },
  { window: [5, 5, 205, 155], width: 50, height: 70, resampleMethod: "bilinear" },
  { resX: 0.00045, bbox: [138.6, 35.46, 138.64, 35.5] },
];

function same(a, b) {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (!Object.is(a[i], b[i])) return false;
  return true;
}

const results = {};
const failures = [];
function record(group, label, got, want) {
  const r = (results[group] ??= { cases: 0, values: 0, identical: 0, bothRefuse: 0, differ: 0 });
  r.cases++;
  let ok;
  if ("error" in want) ok = "error" in got;
  else if ("error" in got) ok = false;
  else {
    ok = got.width === want.width && got.height === want.height && got.bands.length === want.length;
    for (let i = 0; ok && i < want.length; i++) ok = got.bands[i].constructor === want[i].constructor && same(got.bands[i], want[i]);
  }
  if (!ok) {
    r.differ++;
    if (failures.length < 20) {
      const first = !("error" in got) && !("error" in want) ? want.findIndex((w, i) => !same(got.bands[i] ?? [], w)) : -1;
      failures.push({ group, label, got: got.error ?? { width: got.width, height: got.height, type: got.bands[0]?.constructor.name, head: Array.from(got.bands[Math.max(first, 0)]?.slice(0, 6) ?? []) }, want: want.error ?? { width: want.width, height: want.height, type: want[0]?.constructor.name, head: Array.from(want[Math.max(first, 0)]?.slice(0, 6) ?? []) } });
    }
  } else if ("error" in want) r.bothRefuse++;
  else {
    r.identical++;
    r.values += want.reduce((s, b) => s + b.length, 0);
  }
}

const wrap = async (f) => {
  try {
    return await f();
  } catch (e) {
    return { error: String(e.message ?? e) };
  }
};

const served = new Map();
let requests = 0;
let ranged = true;
const server = createServer((req, res) => {
  requests++;
  const body = served.get(new URL(req.url, "http://x").pathname);
  if (!body) return res.writeHead(404).end();
  const range = ranged ? byteRange(req.headers.range, body.length) : null;
  if (range === "bad") return res.writeHead(416).end();
  if (range) {
    res.writeHead(206, { "content-range": `bytes ${range[0]}-${range[1]}/${body.length}`, "content-length": range[1] - range[0] + 1 });
    return res.end(body.subarray(range[0], range[1] + 1));
  }
  res.writeHead(200, { "content-length": body.length }).end(body);
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const base = `http://127.0.0.1:${server.address().port}`;

const meta = {};
const deviations = [];
for (const [label, images, options] of files) {
  const bytes = tiffFile(images, options);
  // geotiff undoes predictors in little-endian order whatever the file's (predictor.js), so a
  // big-endian file is compared with geotiff reading its little-endian twin.
  const twin = options?.little === false ? tiffFile(images, { ...options, little: true }) : bytes;
  const tiff = await fromArrayBuffer(twin.slice().buffer);
  const first = await tiff.getImage();
  const img = { width: first.getWidth(), height: first.getHeight(), samples: first.getSamplesPerPixel() };
  for (const v of variants(img)) {
    const want = await wrap(() => tiff.readRasters({ ...v }));
    const got = await wrap(() => reader.readRaster(rasterSource({ bytes }), { ...v }));
    record("bytes", `${label} ${JSON.stringify(v)}`, got, want);
  }
  // geotiff resamples to `width` x undefined, giving empty bands; this keeps the window's height.
  const wide = await wrap(() => reader.readRaster(rasterSource({ bytes }), { width: 100 }));
  deviations.push({ label: `${label}: width alone`, ok: !("error" in wide) && wide.width === 100 && wide.height === wide.window[3] - wide.window[1] && wide.bands[0].length === 100 * wide.height, why: "geotiff gives empty bands for a width without a height" });
  const whole = await reader.readRaster(rasterSource({ bytes }), {});
  meta[label] = { bbox: same(whole.bbox, first.getBoundingBox()), crs: whole.crs, images: whole.images, bytes: bytes.length };
  if (!meta[label].bbox) failures.push({ group: "meta", label, got: whole.bbox, want: first.getBoundingBox() });
  served.set(`/${encodeURIComponent(label)}.tif`, bytes);
}
// Over HTTP: the COG reads its directories from the first request; a file with them at its end
// is read again with what they need.
const http = {};
for (const label of ["DEM with overviews (COG layout)", "DEM float32 tiled 128 LZW predictor 3", "map RGB planar 2 tiled Deflate", "DEM float32 BigTIFF big-endian"]) {
  const url = `${base}/${encodeURIComponent(label)}.tif`;
  const tiff = await fromUrl(url);
  const counts = { ours: 0, theirs: 0 };
  for (const v of [{ window: [100, 100, 260, 230] }, { bbox: [138.61, 35.47, 138.63, 35.49] }, { width: 64, height: 64 }, {}]) {
    requests = 0;
    const want = await wrap(() => tiff.readRasters({ ...v }));
    counts.theirs += requests;
    requests = 0;
    const got = await wrap(() => reader.readRaster(rasterSource({ url }, 1 << 28), { ...v }));
    counts.ours += requests;
    record("http", `${label} ${JSON.stringify(v)}`, got, want);
  }
  http[label] = counts;
}
ranged = false;
{
  const label = "DEM float32 tiled 64 none";
  const tiff = await fromArrayBuffer(served.get(`/${encodeURIComponent(label)}.tif`).slice().buffer);
  record("http", "a server ignoring Range", await wrap(() => reader.readRaster(rasterSource({ url: `${base}/${encodeURIComponent(label)}.tif` }, 1 << 28), { window: [1, 2, 30, 40] })), await tiff.readRasters({ window: [1, 2, 30, 40] }));
}
server.close();

// --- Refusals ---
const good = tiffFile([dem({ tile: [64, 64], compression: 5 })]);
const cut = (n) => good.subarray(0, n);
const changed = (f) => {
  const b = good.slice();
  f(new DataView(b.buffer), b);
  return b;
};
for (const [label, bytes] of [
  ["not a TIFF", new TextEncoder().encode("GIF89a........")],
  ["an empty file", new Uint8Array(0)],
  ["version 41", changed((v) => v.setUint16(2, 41, true))],
  ["no image directory", changed((v) => v.setUint32(4, 0, true))],
  ["a sample index past the samples", null],
  ["LERC compression", tiffFile([dem({ tile: [64, 64], compression: 34887 })])],
  ["ZSTD compression", tiffFile([dem({ tile: [64, 64], compression: 50000 })])],
]) {
  if (bytes === null) {
    const tiff = await fromArrayBuffer(good.slice().buffer);
    record("refused", label, await wrap(() => reader.readRaster(rasterSource({ bytes: good }), { samples: [3] })), await wrap(() => tiff.readRasters({ samples: [3] })));
    continue;
  }
  const want = await wrap(async () => (await fromArrayBuffer(bytes.slice().buffer)).readRasters());
  record("refused", label, await wrap(() => reader.readRaster(rasterSource({ bytes }), {})), want.error ? want : { error: "should refuse" });
}
// Cut files: geotiff reads past its buffer or stops; only our refusal is checked.
for (const n of [good.length - 100, 4000, 9]) {
  const got = await wrap(() => reader.readRaster(rasterSource({ bytes: cut(n) }), {}));
  deviations.push({ label: `cut at ${n} of ${good.length}`, ok: "error" in got, why: "geotiff reads past its buffer" });
}

let differ = 0;
let total = 0;
for (const [group, r] of Object.entries(results)) {
  differ += r.differ;
  total += r.cases;
  console.log(`${group}: ${r.cases} cases, ${r.values} values identical, ${r.bothRefuse} refused by both, ${r.differ} differ`);
}
const bad = deviations.filter((d) => !d.ok).length + failures.filter((f) => f.group === "meta").length;
console.log(`deviations: ${deviations.length} documented, ${deviations.filter((d) => !d.ok).length} not as documented`);
console.log(`requests: ${JSON.stringify(http)}`);
for (const f of failures) console.log("DIFF", JSON.stringify(f).slice(0, 600));
for (const d of deviations.filter((x) => !x.ok)) console.log("DEVIATION", JSON.stringify(d));
console.log(`${total} cases, ${differ + bad} differ`);
const pkg = async (name) => JSON.parse(await readFile(path.join(ROOT, "bench/node_modules", name, "package.json"), "utf8")).version;
await writeFile(path.join(ROOT, "bench/results/geotiff-golden.json"), JSON.stringify({ env: { node: process.version, geotiff: await pkg("geotiff") }, results, meta, http, deviations, differ: differ + bad }, null, 2) + "\n");
if (differ + bad > 0) process.exit(1);
