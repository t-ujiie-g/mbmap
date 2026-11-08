// Downloads the bench tile sets (GSI, and OpenFreeMap's and Protomaps' for the public styles), the
// public styles' sprites and PLATEAU's 3D Tiles around Tokyo Station, and verifies each against its bench/fixtures/<set>.manifest.json (see
// bench/fixtures/README.md); --update rewrites the manifests, --only=a,b takes those sets alone.
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import path from "node:path";
import { PMTiles } from "pmtiles";
import { ROOT } from "../lib/root.mjs";
import { tilesetSubset } from "../lib/tileset-subset.mjs";

export const TILES = { z: 14, x: [14549, 14555], y: [6449, 6453] };
// [west, south, east, north] in degrees: the 3D Tiles kept are those meeting it and their ancestors.
const TOKYO_STATION = [139.76, 35.677, 139.772, 35.686];
const PLATEAU = "出典：国土交通省 Project PLATEAU（3D都市モデル 建築物モデル 千代田区 2025年度）";
// The vector tiles, standard map images and DEM of TILES, a DEM of Mt Fuji for relief that shows and
// the standard map of the whole world at zooms 0 to 3 for the globe.
const SETS = [
  {
    name: "gsi-bvmap", ext: "pbf", ...TILES,
    url: "https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/{z}/{x}/{y}.pbf",
    attribution: "国土地理院ベクトルタイル提供実験 (GSI Japan)",
  },
  {
    name: "gsi-dem", ext: "png", ...TILES,
    url: "https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png",
    attribution: "国土地理院 標高タイル (GSI Japan)",
  },
  {
    name: "gsi-std", ext: "png", ...TILES,
    url: "https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png",
    attribution: "国土地理院 標準地図 (GSI Japan)",
  },
  {
    name: "gsi-dem-fuji", ext: "png", z: 12, x: [3625, 3628], y: [1616, 1619],
    url: "https://cyberjapandata.gsi.go.jp/xyz/dem_png/{z}/{x}/{y}.png",
    attribution: "国土地理院 標高タイル (GSI Japan)",
  },
  {
    name: "gsi-std-world", ext: "png",
    levels: [0, 1, 2, 3].map((z) => ({ z, x: [0, (1 << z) - 1], y: [0, (1 << z) - 1] })),
    url: "https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png",
    attribution: "国土地理院 標準地図 (GSI Japan)",
  },
  {
    name: "ofm-planet", ext: "pbf", ...TILES,
    url: "https://tiles.openfreemap.org/planet/20261101_080013_pt/{z}/{x}/{y}.pbf",
    attribution: "OpenFreeMap © OpenMapTiles Data from OpenStreetMap",
  },
  {
    name: "protomaps", ext: "pbf", ...TILES,
    pmtiles: "https://build.protomaps.com/20261103.pmtiles",
    attribution: "Protomaps © OpenStreetMap contributors",
  },
  { name: "sprites", files: sprites(), attribution: "OpenMapTiles styles (CC-BY 4.0), OpenFreeMap sprites (MIT)" },
  {
    name: "plateau-chiyoda", box: TOKYO_STATION, attribution: PLATEAU,
    tileset: `https://assets.cms.plateau.reearth.io/assets/72/e900e5-938c-4376-a9de-a124b270880c/13101_chiyoda-ku_pref_2025_citygml_1_op_bldg_3dtiles_13101_chiyoda-ku_lod2_no_texture/tileset.json`,
  },
];

// The public styles' sprites (style/public-styles.mjs), each at 1x and 2x.
function sprites() {
  const omt = (name) => `https://raw.githubusercontent.com/openmaptiles/${name}-gl-style/gh-pages/sprite`;
  const bases = {
    "osm-bright": omt("osm-bright"), positron: omt("positron"), "dark-matter": omt("dark-matter"),
    "maptiler-basic": omt("maptiler-basic"), ofm: "https://tiles.openfreemap.org/sprites/ofm_f384/ofm",
  };
  const files = {};
  for (const [name, base] of Object.entries(bases))
    for (const suffix of ["", "@2x"]) for (const ext of ["json", "png"]) files[`${name}/sprite${suffix}.${ext}`] = `${base}${suffix}.${ext}`;
  return files;
}
const update = process.argv.includes("--update");
const only = process.argv.find((a) => a.startsWith("--only="))?.slice(7).split(",");
const archives = new Map();

// Network errors, 429 and 5xx are tried again with backoff; other statuses fail at once.
async function download(url, what, attempts = 4) {
  for (let i = 1; ; i++) {
    let res, reason;
    try {
      res = await fetch(url);
      if (res.ok) return Buffer.from(await res.arrayBuffer());
      reason = `HTTP ${res.status}`;
    } catch (e) {
      reason = e.cause?.code ?? e.message;
    }
    if (res && !res.ok && res.status !== 429 && res.status < 500) throw new Error(`${what}: ${reason}`);
    if (i >= attempts) throw new Error(`${what}: ${reason} (${attempts} attempts)`);
    await new Promise((r) => setTimeout(r, 1000 * 2 ** (i - 1)));
  }
}

// A tile read from a PMTiles archive by range requests, decompressed.
async function fromArchive(url, { z, x, y }) {
  if (!archives.has(url)) archives.set(url, new PMTiles(url));
  const tile = await archives.get(url).getZxy(z, x, y);
  if (!tile) throw new Error(`${url}: no tile ${z}/${x}/${y}`);
  return Buffer.from(tile.data);
}
const hash = (b) => createHash("sha256").update(b).digest("hex");

let failed = false;
for (const set of SETS.filter((s) => !only || only.includes(s.name))) {
  const dir = path.join(ROOT, "bench/fixtures", set.name);
  const manifestPath = path.join(ROOT, `bench/fixtures/${set.name}.manifest.json`);
  let manifest = null;
  try { manifest = JSON.parse(await readFile(manifestPath, "utf8")); } catch {}
  const jobs = [];
  if (set.tileset) {
    jobs.push({ key: "tileset.json", file: path.join(dir, "tileset.json"), url: set.tileset });
  } else if (set.files) {
    for (const [key, url] of Object.entries(set.files)) jobs.push({ key, file: path.join(dir, key), url });
  } else {
    for (const { z, x: xs, y: ys } of set.levels ?? [set])
      for (let x = xs[0]; x <= xs[1]; x++)
        for (let y = ys[0]; y <= ys[1]; y++) {
          const key = `${z}/${x}/${y}`;
          const url = set.url?.replace("{z}", z).replace("{x}", x).replace("{y}", y);
          jobs.push({ key, file: path.join(dir, `${key}.${set.ext}`), url, z, x, y });
        }
  }
  const entries = {};
  let mismatches = 0;
  const fetchJob = async (job) => {
    const { key, file } = job;
    let buf = await readFile(file).catch(() => null);
    const expected = manifest?.tiles?.[key]?.sha256;
    if (!buf || (expected && hash(buf) !== expected)) {
      buf = set.pmtiles ? await fromArchive(set.pmtiles, job) : await download(job.url, `${set.name} ${key}`);
      await mkdir(path.dirname(file), { recursive: true });
      // Only bytes the manifest pins (or --update accepts) go where goldens read them.
      if (!expected || update || hash(buf) === expected) await writeFile(file, buf);
      else await rm(file, { force: true });
    }
    const sha256 = hash(buf);
    if (expected && expected !== sha256) {
      mismatches++;
      console.warn(`${set.name} ${key}: upstream content changed (sha256 ${sha256})${update ? "" : "; not kept"}`);
    }
    entries[key] = { bytes: buf.length, sha256 };
    return buf;
  };
  const worker = async () => {
    for (let job; (job = jobs.shift()); ) await fetchJob(job);
  };
  // A set that cannot be fetched (a Protomaps build is kept for a while only) leaves the others to go on.
  try {
    // A tileset is kept byte for byte; its contents are those of the tiles that meet the set's box.
    if (set.tileset) {
      const tileset = JSON.parse((await fetchJob(jobs.shift())).toString("utf8"));
      for (const key of tilesetSubset(tileset, set.box))
        jobs.push({ key, file: path.join(dir, key), url: new URL(key, set.tileset).href });
    }
    await Promise.all([worker(), worker(), worker(), worker()]);
  } catch (e) {
    console.error(`${set.name}: not fetched (${e.message})`);
    failed = true;
    continue;
  }
  if (!manifest || update) {
    const tiles = Object.fromEntries(Object.entries(entries).sort());
    const total = Object.values(tiles).reduce((a, t) => a + t.bytes, 0);
    await writeFile(manifestPath, JSON.stringify({
      source: set.url ?? set.pmtiles ?? set.tileset ?? "see bench/maplibre/fetch-tiles.mjs",
      ...(set.box && { box: set.box }),
      attribution: set.attribution,
      fetched: new Date().toISOString().slice(0, 10),
      totalBytes: total,
      tiles,
    }, null, 2) + "\n");
    console.log(`${set.name}: wrote manifest, ${Object.keys(tiles).length} tiles, ${total} bytes`);
  } else if (mismatches) {
    console.error(`${set.name}: ${mismatches} tiles differ from the manifest; results are not comparable. Re-run with --update to accept.`);
    failed = true;
  } else {
    console.log(`${set.name}: fixtures OK, ${Object.keys(entries).length} tiles`);
  }
}
if (failed) process.exitCode = 1;
