// Public MapLibre styles read by `npm run style:compat`, pinned by commit and sha256.
// Designs: OpenMapTiles styles CC-BY 4.0 © OpenMapTiles (code BSD-3-Clause); OpenFreeMap styles
// derive from them (MIT); MapLibre demotiles BSD-3-Clause. See bench/fixtures/README.md.
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";

const gh = (repo, commit, file) => `https://raw.githubusercontent.com/${repo}/${commit}/${file}`;
const OMT = (name, commit) => gh(`openmaptiles/${name}-gl-style`, commit, "style.json");
const OFM = (name) => gh("hyperknot/openfreemap-styles", "006ea5796803ba2df4330888836cb0a8f17473b4", `styles/${name}/style.json`);

export const PUBLIC_STYLES = {
  "osm-bright": { url: OMT("osm-bright", "563b249f7ae71528b1f1e327cb9c019d0dda4c50"), sha256: "f22ea32155549fb694581d3623ecbb32edea68f599e19861f06b4c62d1d524ce" },
  positron: { url: OMT("positron", "bed9a6349dfb431bd8a6646101d0977b59c591dd"), sha256: "084275f4133cd6b1d02d852db6cb10c83a70d50571d0759617c12e6742a33099" },
  "dark-matter": { url: OMT("dark-matter", "d17442cb66bad8c82bda59d199d5dafeead410cf"), sha256: "0e3e1f4b26a1af8243f7fbbb89f3afec530c2eafbf5ba41c90210c40508c843d" },
  "maptiler-basic": { url: OMT("maptiler-basic", "65b58c5d715b470f8f381a6c519a554653e89d98"), sha256: "73ccf7ddbd2a753ddaa0f4e326bd59910fa24950cc15be31c9d413b5a5bfcb5d" },
  "ofm-liberty": { url: OFM("liberty"), sha256: "e6656627d04035c9c8ac04397d260b9a74ebdb69543dce7578668be246797c00" },
  "ofm-bright": { url: OFM("bright"), sha256: "b26439eb4247c2a3764efa46dc06deae18a71b8089d083d42a9d5df852872c60" },
  "ofm-positron": { url: OFM("positron"), sha256: "3c983bbe247bb116cbfd5192422ea3c8a5d3230362657aac65cdf8c546f8e913" },
  demotiles: { url: gh("maplibre/demotiles", "601ae60796ceceda2cbd2ed3d2ea92d17a84be4b", "style.json"), sha256: "dd86fd257f9895da23b7da5dac62829a0b25ab458f71b06a3e06857b076caf06" },
};

const CACHE = path.join(ROOT, "bench/fixtures/styles");

// The pinned style `name`, fetched once into bench/fixtures/styles/ and checked against its sha256.
export async function loadPublicStyle(name, { url, sha256 } = PUBLIC_STYLES[name]) {
  const file = path.join(CACHE, `${name}.json`);
  let bytes = await readFile(file).catch(() => null);
  if (!bytes) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`${name}: ${res.status} ${url}`);
    bytes = Buffer.from(await res.arrayBuffer());
  }
  const hash = createHash("sha256").update(bytes).digest("hex");
  if (hash !== sha256) throw new Error(`${name}: sha256 ${hash}, expected ${sha256}`);
  await mkdir(CACHE, { recursive: true });
  await writeFile(file, bytes);
  return JSON.parse(bytes.toString("utf8"));
}
