// Builds dist/: the facade and the files it loads, `<mb-map>`, the ui, search, draw, services, GeoJSON,
// analysis, geodesic, 3d and data modules, and their workers with their wasm. Usage: node scripts/build.mjs
import { execFileSync } from "node:child_process";
import { copyFile, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const PKG = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ROOT = path.dirname(PKG);
const DIST = path.join(PKG, "dist");
const run = (cmd, args, cwd) => execFileSync(cmd, args, { cwd, stdio: "inherit" });

// No wasm-opt: it made the wasm-gc worker slower in every browser (AGENTS.md §4).
const WASM = {
  worker: "mbmap.wasm",
  geojson_worker: "geojson.wasm",
  geojson_props_worker: "geojson-properties.wasm",
  analysis_worker: "analysis.wasm",
  geometry_worker: "geometry.wasm",
  relate_worker: "relate.wasm",
  shapes_worker: "shapes.wasm",
  surface_worker: "surface.wasm",
  viewshed_worker: "viewshed.wasm",
  route_worker: "route.wasm",
  proj_worker: "proj.wasm",
  geodesic_worker: "geodesic.wasm",
  model_worker: "3d.wasm",
  data_worker: "data.wasm",
  xml_worker: "xml.wasm",
  geotiff_worker: "geotiff.wasm",
  services_worker: "services.wasm",
};

run("moon", ["build", "bundle/main", "--target", "js", "--release"], ROOT);
run("moon", ["build", ...Object.keys(WASM), "--target", "wasm-gc", "--release"], ROOT);
await rm(DIST, { recursive: true, force: true });
await mkdir(DIST);

const common = { bundle: true, minify: true, format: "esm", target: "es2022", logLevel: "warning", legalComments: "none" };
const escaped = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
// Leaves `files` (what the source imports: the file it loads instead) out of a bundle.
const separate = (files) => ({
  name: "separate-files",
  setup: (b) => b.onResolve({ filter: new RegExp(`^(${Object.keys(files).map(escaped).join("|")})$`) }, (a) => ({ path: files[a.path], external: true })),
});
const same = (names) => Object.fromEntries(names.map((name) => [`./${name}.js`, `./${name}.js`]));

// Each loaded only by maps that need it.
const MAP_PARTS = same(["geojson", "pmtiles", "legacy", "sprite", "media", "custom", "export", "tilejson-merge", "geotiff-source"]);
// Imported by the display worker on first use.
const WORKER_PARTS = { "./symbols.mjs": "./worker-labels.js", "./pmtiles.mjs": "./worker-pmtiles.js", "./query.mjs": "./worker-query.js" };
// Imported by the data worker on first use.
const DATA_PARTS = { "../../npm/src/zip.ts": "./data-zip.js", "./crs.mjs": "./data-crs.js", "./fgb.mjs": "./data-fgb.js", "./geotiff.mjs": "./data-geotiff.js", "./reproject.mjs": "./data-reproject.js" };
// Loaded on the first PROJ string.
const PROJSTRING = separate(same(["projstring"]));

// Output file, source and what stays out of it. GeoTIFF sources ask mbmap/data's worker for their
// tiles, so data.js is imported; the element likewise imports the main entry rather than a second
// copy; the controllers only take a `Map`, so no part of the main entry is bundled into them.
const ENTRIES = [
  ["index.js", "npm/src/index.ts", { alias: { "mbmap-engine": path.join(ROOT, "_build/js/release/build/bundle/main/main.js") }, plugins: [separate(MAP_PARTS)] }],
  ...Object.keys(MAP_PARTS).filter((file) => file !== "./geotiff-source.js").map((file) => [file.slice(2), `npm/src/${file.slice(2, -3)}.ts`]),
  ["geotiff-source.js", "npm/src/geotiff-source.ts", { plugins: [separate({ "./data": "./data.js" })] }],
  ["ui.js", "npm/src/ui.ts"],
  ["search.js", "npm/src/search.ts"],
  ["draw.js", "npm/src/draw.ts"],
  ["services.js", "npm/src/services.ts", { plugins: [separate({ "./services/gml": "./services-gml.js" })] }],
  ["services-gml.js", "npm/src/services/gml.ts"],
  ["services-worker.js", "services_worker/js/worker.mjs"],
  ["geojson-worker.js", "geojson_worker/js/worker.mjs"],
  ["worker.js", "worker/js/worker.mjs", { plugins: [separate(WORKER_PARTS)] }],
  ...Object.entries(WORKER_PARTS).map(([source, file]) => [file.slice(2), path.join("worker/js", source)]),
  ["analysis.js", "npm/src/analysis.ts", { plugins: [PROJSTRING] }],
  ["projstring.js", "npm/src/projstring.ts"],
  ["analysis-worker.js", "analysis_worker/js/worker.mjs", { plugins: [separate({ "./viewshed.mjs": "./analysis-viewshed.js" })] }],
  ["analysis-viewshed.js", "analysis_worker/js/viewshed.mjs"],
  ["geodesic.js", "npm/src/geodesic.ts"],
  ["geodesic-worker.js", "geodesic_worker/js/worker.mjs"],
  ["3d.js", "npm/src/3d.ts"],
  ["3d-worker.js", "model_worker/js/worker.mjs"],
  ["data.js", "npm/src/data.ts", { plugins: [PROJSTRING] }],
  ["data-worker.js", "data_worker/js/worker.mjs", { plugins: [separate(DATA_PARTS)] }],
  ...Object.entries(DATA_PARTS).map(([source, file]) => [file.slice(2), path.join("data_worker/js", source)]),
  ["prjwkt.js", "npm/src/prjwkt.ts"],
  ["element.js", "element/element.ts", { plugins: [separate({ mbmap: "./index.js" })] }],
];
for (const [file, source, options] of ENTRIES) {
  await build({ ...common, ...options, entryPoints: [path.join(ROOT, source)], outfile: path.join(DIST, file) });
}
for (const [name, file] of Object.entries(WASM)) {
  await copyFile(path.join(ROOT, `_build/wasm-gc/release/build/${name}/${name}.wasm`), path.join(DIST, file));
}
const tsc = path.join(PKG, "node_modules/typescript/bin/tsc");
run(process.execPath, [tsc, "-p", path.join(PKG, "tsconfig.json")], PKG);
run(process.execPath, [tsc, "-p", path.join(ROOT, "element/tsconfig.json")], PKG);
// Relative imports in the declarations end in .js, which `moduleResolution: node16`
// and `nodenext` require (the sources leave the extension out or write .ts).
for (const file of await readdir(DIST, { recursive: true })) {
  if (!file.endsWith(".d.ts")) continue;
  const at = path.join(DIST, file);
  const text = await readFile(at, "utf8");
  const fixed = text.replace(/((?:from |import\()")(\.{1,2}\/[^"]*?)(\.ts)?"/g, (_, lead, spec) => `${lead}${spec}.js"`);
  if (fixed !== text) await writeFile(at, fixed);
}
for (const f of ["LICENSE", "NOTICE"]) await copyFile(path.join(ROOT, f), path.join(PKG, f));
