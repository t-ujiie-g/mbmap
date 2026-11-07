// services.wasm's ArcGIS readers on live public layers (AGENTS.md §1 `esri:golden`): f=json vs @terraformer/arcgis
// 2.2.2 exactly; f=pbf attributes and ids vs arcgis-pbf-parser 0.0.4, geometry within quantization of f=json.
// Writes bench/results/esri-golden.json; behind a proxy Node needs NODE_USE_ENV_PROXY=1.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { arcgisToGeoJSON } from "@terraformer/arcgis";
import decodePbf from "arcgis-pbf-parser";
import { readEsri, servicesImports } from "../../services_worker/js/read.mjs";
import { same, wasmFile } from "../data/common.mjs";
import { ROOT } from "../lib/root.mjs";

let exports = null;
({ instance: { exports } } = await WebAssembly.instantiate(await wasmFile("services_worker"), servicesImports(() => exports)));

const SAMPLE = "https://sampleserver6.arcgisonline.com/arcgis/rest/services";
const HOSTED = "https://services.arcgis.com/P3ePLMYs2RVChkJx/ArcGIS/rest/services";
// Layers read as `f=json`; those that also answer `f=pbf` (FeatureServers) after them.
const JSON_LAYERS = [`${SAMPLE}/SampleWorldCities/MapServer/0`, `${SAMPLE}/USA/MapServer/1`, `${SAMPLE}/USA/MapServer/2`, `${SAMPLE}/USA/MapServer/3`];
const PBF_LAYERS = [
  `${SAMPLE}/Military/FeatureServer/3`,
  `${SAMPLE}/Military/FeatureServer/4`,
  `${SAMPLE}/Military/FeatureServer/9`,
  `${SAMPLE}/Wildfire/FeatureServer/1`,
  `${SAMPLE}/Wildfire/FeatureServer/2`,
  `${HOSTED}/USA_Major_Cities_/FeatureServer/0`,
  `${HOSTED}/World_Countries_(Generalized)/FeatureServer/0`,
];
// A coordinate of `f=pbf` lies within its quantization of `f=json`'s.
const QUANTIZED = 1e-7;

const results = [];
let failed = 0;
const report = (r) => {
  if (!r.ok) failed++;
  results.push(r);
  console.log(JSON.stringify(r).slice(0, 400));
};
const query = (layer, format, count) => `${layer}/query?where=1%3D1&outFields=*&outSR=4326&resultRecordCount=${count}&f=${format}`;
async function bytes(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
  return new Uint8Array(await res.arrayBuffer());
}
// Features without attributes have `{}` for properties in mbmap and null in terraformer; an empty
// geometry (`"rings": []`) is null in mbmap, as in its other readers.
const empty = (g) => g && Array.isArray(g.coordinates) && g.coordinates.length === 0;
const normalized = (features) => features.map((f) => ({ ...f, properties: f.properties ?? {}, geometry: empty(f.geometry) ? null : f.geometry }));
// The index and the two values of the first feature where `a` and `b` differ.
function firstDiff(a, b, eps = 0) {
  if (a.length !== b.length) return { at: "length", ours: a.length, theirs: b.length };
  const i = a.findIndex((f, k) => !same(f, b[k], eps));
  return i < 0 ? null : { at: i, ours: JSON.stringify(a[i]).slice(0, 300), theirs: JSON.stringify(b[i]).slice(0, 300) };
}

for (const layer of [...JSON_LAYERS, ...PBF_LAYERS]) {
  try {
    const json = await bytes(query(layer, "json", 1000));
    const doc = JSON.parse(new TextDecoder().decode(json));
    const theirs = normalized(arcgisToGeoJSON(doc, doc.objectIdFieldName).features);
    const ours = readEsri(exports, json, "json");
    const d = firstDiff(ours.features, theirs) ?? (ours.exceeded === (doc.exceededTransferLimit === true) ? null : { at: "exceeded", ours: ours.exceeded });
    report({ check: "f=json", layer, features: ours.features.length, ok: d === null && ours.features.length > 0, ...(d && { diff: d }) });
    if (!PBF_LAYERS.includes(layer)) continue;
    const pbf = await bytes(query(layer, "pbf", 1000));
    const ref = decodePbf(pbf);
    const read = readEsri(exports, pbf, "pbf");
    const attributes = (fs) => fs.map((f) => ({ id: f.id ?? null, properties: f.properties }));
    const dp =
      firstDiff(attributes(read.features), attributes(ref.featureCollection.features)) ??
      firstDiff(read.features.map((f) => f.geometry), theirs.map((f) => f.geometry), QUANTIZED) ??
      (read.exceeded === (ref.exceededTransferLimit === true) ? null : { at: "exceeded", ours: read.exceeded });
    report({ check: "f=pbf", layer, features: read.features.length, bytes: [pbf.length, json.length], ok: dp === null && read.features.length > 0, ...(dp && { diff: dp }) });
  } catch (e) {
    report({ check: "esri", layer, ok: false, error: String(e) });
  }
}

// Malformed input is refused with a message, never read past.
const refused = (input, format) => {
  try {
    readEsri(exports, input, format);
    return false;
  } catch (e) {
    return /^malformed ArcGIS (JSON|PBF)/.test(e.message);
  }
};
const hostile = [
  [new TextEncoder().encode('{"features":[{"geometry":{"rings":[[[0,0],[1]]]}}]}'), "json"],
  [new TextEncoder().encode('{"error":{"code":498,"message":"Invalid token."}}'), "json"],
  [new Uint8Array([0x12, 0x05, 0x0a, 0x7f, 0x01]), "pbf"],
  [new Uint8Array([0x12, 0x03, 0x0a, 0x01, 0x7a, 0x00]), "pbf"],
  [new Uint8Array(0), "pbf"],
];
report({ check: "malformed", cases: hostile.length, ok: hostile.every(([b, f]) => refused(b, f)) });

await writeFile(path.join(ROOT, "bench/results/esri-golden.json"), JSON.stringify({ env: { "@terraformer/arcgis": "2.2.2", "arcgis-pbf-parser": "0.0.4", node: process.version }, results }, null, 2) + "\n");
console.log(`${results.length - failed} of ${results.length} ok`);
if (failed) process.exit(1);
