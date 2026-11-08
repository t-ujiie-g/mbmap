// Checks dist/ against VISION §2/§3's per-entry gzip budgets: every file belongs
// to one entry and each entry's JS references only its own files. Writes
// bench/results/npm-size.json (and $GITHUB_STEP_SUMMARY); exits 1 on failure.
import { appendFile, readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";
import { build } from "esbuild";
import { referencesOf } from "./references.mjs";

const PKG = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const DIST = path.join(PKG, "dist");

// `files` are what a user of the entry loads on top of the entries it builds
// on; `references` the dist files its JS may import or load by URL.
const ENTRIES = [
  { name: "mbmap", files: ["index.js"], budget: 135_000, references: ["./geojson.js", "./pmtiles.js", "./legacy.js", "./sprite.js", "./media.js", "./custom.js", "./export.js", "./tilejson-merge.js", "./geotiff-source.js", "./worker.js", "./mbmap.wasm"] },
  { name: "GeoJSON sources (loaded by mbmap when a style has one)", files: ["geojson.js"], budget: 5_000, references: ["./geojson-worker.js", "./geojson.wasm", "./geojson-properties.wasm"] },
  { name: "PMTiles headers (loaded by mbmap when a style has a pmtiles:// source)", files: ["pmtiles.js"], budget: 2_000, references: [] },
  { name: "GeoTIFF sources (loaded by mbmap with the first one; tiles by mbmap/data)", files: ["geotiff-source.js"], budget: 1_000, references: ["./data.js"] },
  { name: "legacy filters and functions (loaded by mbmap when a style has them)", files: ["legacy.js"], budget: 5_000, references: [] },
  { name: "sprite sheets (loaded by mbmap when a style has a sprite)", files: ["sprite.js"], budget: 2_000, references: [] },
  { name: "image, video and canvas sources (loaded by mbmap when a style has one)", files: ["media.js"], budget: 3_000, references: [] },
  { name: "custom layers (loaded by mbmap with the first one)", files: ["custom.js"], budget: 3_000, references: [] },
  { name: "image export (loaded by mbmap with the first toBlob)", files: ["export.js"], budget: 1_000, references: [] },
  { name: "TileJSON merging (loaded by mbmap with the first source given by url)", files: ["tilejson-merge.js"], budget: 1_000, references: [] },
  { name: "mbmap/element (on top of mbmap)", files: ["element.js"], budget: 5_000, references: ["./index.js"] },
  { name: "mbmap/ui (every controller)", files: ["ui.js"], budget: 10_000, references: [] },
  { name: "mbmap/search", files: ["search.js"], budget: 5_000, references: [] },
  { name: "mbmap/services", files: ["services.js"], budget: 12_000, references: ["./services-gml.js", "./services-worker.js", "./services.wasm"] },
  { name: "WFS GML (loaded by mbmap/services with the first GML answer)", files: ["services-gml.js"], budget: 2_500, references: [] },
  { name: "services worker (ArcGIS f=json and f=pbf; loaded by mbmap/services on the first such read)", files: ["services-worker.js", "services.wasm"], budget: 21_000, references: [] },
  { name: "mbmap/draw", files: ["draw.js"], budget: 10_000, references: [] },
  { name: "display worker", files: ["worker.js", "mbmap.wasm"], budget: 100_000, references: ["./worker-labels.js", "./worker-pmtiles.js", "./worker-query.js"] },
  { name: "labels (loaded by the display worker with the first tile that has them)", files: ["worker-labels.js"], budget: 10_000, references: [] },
  { name: "PMTiles tiles (loaded by the display worker with the first pmtiles:// tile)", files: ["worker-pmtiles.js"], budget: 3_000, references: [] },
  { name: "feature queries (loaded by the display worker with the first query)", files: ["worker-query.js"], budget: 1_500, references: [] },
  { name: "GeoJSON worker", files: ["geojson-worker.js", "geojson.wasm"], budget: 30_000, references: [] },
  { name: "GeoJSON worker with expressions (loaded instead for sources with clusterProperties)", files: ["geojson-worker.js", "geojson-properties.wasm"], budget: 50_000, references: [] },
  { name: "mbmap/analysis", files: ["analysis.js"], budget: 9_000, references: ["./projstring.js", "./analysis-worker.js", "./analysis.wasm", "./geometry.wasm", "./relate.wasm", "./shapes.wasm", "./surface.wasm", "./viewshed.wasm", "./route.wasm", "./proj.wasm"] },
  { name: "PROJ strings (loaded by mbmap/analysis and mbmap/data on the first one)", files: ["projstring.js"], budget: 5_000, references: [] },
  { name: "analysis worker", files: ["analysis-worker.js", "analysis.wasm"], budget: 31_000, references: ["./analysis-viewshed.js"] },
  { name: "geometry (loaded by the analysis worker on first use)", files: ["geometry.wasm"], budget: 50_000, references: [] },
  { name: "spatial relations (DE-9IM; loaded by the analysis worker on first use)", files: ["relate.wasm"], budget: 30_000, references: [] },
  { name: "shapes (simplify, hulls, Delaunay, Voronoi, line slices; loaded by the analysis worker on first use)", files: ["shapes.wasm"], budget: 30_000, references: [] },
  { name: "surfaces (grids, IDW, clusters, contours, density; loaded by the analysis worker on first use)", files: ["surface.wasm"], budget: 30_000, references: [] },
  { name: "viewshed (GDAL's; loaded by the analysis worker on first use)", files: ["viewshed.wasm", "analysis-viewshed.js"], budget: 12_000, references: [] },
  { name: "routing (geojson-path-finder; loaded by the analysis worker on first use)", files: ["route.wasm"], budget: 17_000, references: [] },
  { name: "coordinate systems (loaded by the analysis and data workers on first use)", files: ["proj.wasm"], budget: 25_000, references: [] },
  { name: "mbmap/geodesic", files: ["geodesic.js"], budget: 2_000, references: ["./geodesic-worker.js", "./geodesic.wasm"] },
  { name: "geodesic worker", files: ["geodesic-worker.js", "geodesic.wasm"], budget: 15_000, references: [] },
  { name: "mbmap/data", files: ["data.js"], budget: 6_000, references: ["./projstring.js", "./data-worker.js", "./data.wasm", "./proj.wasm", "./prjwkt.js", "./xml.wasm", "./geotiff.wasm"] },
  { name: "data worker", files: ["data-worker.js", "data.wasm"], budget: 41_000, references: ["./data-zip.js", "./data-crs.js", "./data-fgb.js", "./data-geotiff.js", "./data-reproject.js"] },
  { name: "zip archives (loaded by the data worker with the first one)", files: ["data-zip.js"], budget: 2_000, references: [] },
  { name: "FlatGeobuf headers, index and range requests (loaded by the data worker with the first one)", files: ["data-fgb.js"], budget: 2_500, references: [] },
  { name: "reprojected sources' tiles (loaded by the data worker with the first one)", files: ["data-reproject.js"], budget: 2_000, references: [] },
  { name: "coordinates from another CRS (loaded by the data worker with proj.wasm)", files: ["data-crs.js"], budget: 1_500, references: [] },
  { name: ".prj WKT (loaded by the data worker on the first .prj)", files: ["prjwkt.js"], budget: 4_000, references: [] },
  { name: "KML and GPX (loaded by the data worker on the first such read)", files: ["xml.wasm"], budget: 27_000, references: [] },
  { name: "GeoTIFF (loaded by the data worker on the first raster read)", files: ["geotiff.wasm", "data-geotiff.js"], budget: 20_000, references: [] },
];

const failures = [];
const owned = new Set(ENTRIES.flatMap((e) => e.files));
for (const f of await readdir(DIST)) {
  if (/\.(js|wasm)$/.test(f) && !owned.has(f)) failures.push(`${f} belongs to no entry (give it a budget in scripts/size.mjs)`);
}
const rows = [];
for (const e of ENTRIES) {
  let bytes = 0;
  for (const f of e.files) {
    const data = await readFile(path.join(DIST, f));
    bytes += gzipSync(data, { level: 9 }).length;
    if (f.endsWith(".js")) {
      for (const r of referencesOf(data.toString())) {
        if (!e.references.includes(r)) failures.push(`${e.name}: ${f} references ${r}`);
      }
    }
  }
  if (bytes > e.budget) failures.push(`${e.name}: ${bytes} bytes is over its budget of ${e.budget}`);
  rows.push({ name: e.name, bytes, budget: e.budget });
}

// A page pays for the `mbmap/ui` controllers it imports: each alone, tree-shaken from dist/ui.js.
const UI_CONTROLLER_BUDGET = 2_000;
// The attribute table also serves the field editor (setColumns, passing): 2026-11-07, user decision.
const UI_CONTROLLER_BUDGETS = { createAttributeTable: 2_200 };
const uiSource = await readFile(path.join(PKG, "src/ui.ts"), "utf8");
for (const name of [...new Set(uiSource.match(/\bcreate[A-Z]\w*/g))]) {
  const out = await build({
    stdin: { contents: `export { ${name} } from "./ui.js";`, resolveDir: DIST, loader: "js" },
    bundle: true,
    minify: true,
    format: "esm",
    write: false,
    logLevel: "silent",
  });
  const bytes = gzipSync(out.outputFiles[0].contents, { level: 9 }).length;
  const budget = UI_CONTROLLER_BUDGETS[name] ?? UI_CONTROLLER_BUDGET;
  if (bytes > budget) failures.push(`mbmap/ui ${name}: ${bytes} bytes is over its budget of ${budget}`);
  rows.push({ name: `mbmap/ui ${name} alone`, bytes, budget });
}

const kb = (n) => `${(n / 1000).toFixed(1)}KB`;
const lines = ["| entry | gzip | budget |", "|---|---|---|", ...rows.map((r) => `| ${r.name} | ${kb(r.bytes)} | ${kb(r.budget)} |`)];
console.log(lines.join("\n"));
const version = JSON.parse(await readFile(path.join(PKG, "package.json"), "utf8")).version;
await writeFile(
  path.join(PKG, "../bench/results/npm-size.json"),
  JSON.stringify({ env: { package: `mbmap@${version}`, compression: "gzip -9" }, rows }, null, 2) + "\n",
);
if (process.env.GITHUB_STEP_SUMMARY) await appendFile(process.env.GITHUB_STEP_SUMMARY, `## Bundle sizes\n\n${lines.join("\n")}\n`);
if (failures.length > 0) {
  for (const f of failures) console.error(f);
  process.exit(1);
}
