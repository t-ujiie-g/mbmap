// Builds dist/: the facade, `<mb-map>`, the GeoJSON, analysis, geodesic and
// data modules and their workers with their wasm. Usage: node scripts/build.mjs
import { execFileSync } from "node:child_process";
import { copyFile, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const PKG = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const ROOT = path.dirname(PKG);
const DIST = path.join(PKG, "dist");
const run = (cmd, args, cwd) => execFileSync(cmd, args, { cwd, stdio: "inherit" });

run("moon", ["build", "bundle/main", "--target", "js", "--release"], ROOT);
run("moon", ["build", "worker", "--target", "wasm-gc", "--release"], ROOT);
run("moon", ["build", "geojson_worker", "--target", "wasm-gc", "--release"], ROOT);
run("moon", ["build", "geojson_props_worker", "--target", "wasm-gc", "--release"], ROOT);
run("moon", ["build", "analysis_worker", "--target", "wasm-gc", "--release"], ROOT);
run("moon", ["build", "geometry_worker", "--target", "wasm-gc", "--release"], ROOT);
run("moon", ["build", "proj_worker", "--target", "wasm-gc", "--release"], ROOT);
run("moon", ["build", "geodesic_worker", "--target", "wasm-gc", "--release"], ROOT);
run("moon", ["build", "data_worker", "--target", "wasm-gc", "--release"], ROOT);
run("moon", ["build", "xml_worker", "--target", "wasm-gc", "--release"], ROOT);
await rm(DIST, { recursive: true, force: true });
await mkdir(DIST);

const common = { bundle: true, minify: true, format: "esm", target: "es2022", logLevel: "warning", legalComments: "none" };
// The GeoJSON module stays a file of its own, loaded only by maps that need it.
const geojsonEntry = { name: "geojson-entry", setup: (b) => b.onResolve({ filter: /^\.\/(geojson|pmtiles|legacy|sprite|media|custom|export|tilejson-merge)\.js$/ }, (a) => ({ path: a.path, external: true })) };
await build({
  ...common,
  entryPoints: [path.join(PKG, "src/index.ts")],
  outfile: path.join(DIST, "index.js"),
  alias: { "mbmap-engine": path.join(ROOT, "_build/js/release/build/bundle/main/main.js") },
  plugins: [geojsonEntry],
});
await build({ ...common, entryPoints: [path.join(PKG, "src/geojson.ts")], outfile: path.join(DIST, "geojson.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/pmtiles.ts")], outfile: path.join(DIST, "pmtiles.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/legacy.ts")], outfile: path.join(DIST, "legacy.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/sprite.ts")], outfile: path.join(DIST, "sprite.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/media.ts")], outfile: path.join(DIST, "media.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/custom.ts")], outfile: path.join(DIST, "custom.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/export.ts")], outfile: path.join(DIST, "export.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/tilejson-merge.ts")], outfile: path.join(DIST, "tilejson-merge.js") });
// The controllers only take a `Map`: no part of the main entry is bundled into them.
await build({ ...common, entryPoints: [path.join(PKG, "src/ui.ts")], outfile: path.join(DIST, "ui.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/search.ts")], outfile: path.join(DIST, "search.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/draw.ts")], outfile: path.join(DIST, "draw.js") });
await build({ ...common, entryPoints: [path.join(ROOT, "geojson_worker/js/worker.mjs")], outfile: path.join(DIST, "geojson-worker.js") });
// Labels, PMTiles and queries stay files of their own, imported by the display worker on first use.
const WORKER_PARTS = { "./symbols.mjs": "worker-labels.js", "./pmtiles.mjs": "worker-pmtiles.js", "./query.mjs": "worker-query.js" };
const workerParts = { name: "worker-parts", setup: (b) => b.onResolve({ filter: /^\.\/(symbols|pmtiles|query)\.mjs$/ }, (a) => ({ path: `./${WORKER_PARTS[a.path]}`, external: true })) };
await build({ ...common, entryPoints: [path.join(ROOT, "worker/js/worker.mjs")], outfile: path.join(DIST, "worker.js"), plugins: [workerParts] });
for (const [source, file] of Object.entries(WORKER_PARTS)) {
  await build({ ...common, entryPoints: [path.join(ROOT, "worker/js", source)], outfile: path.join(DIST, file) });
}
// The PROJ string parser stays a file of its own, loaded on the first PROJ string.
const projstringEntry = { name: "projstring-entry", setup: (b) => b.onResolve({ filter: /^\.\/projstring\.js$/ }, () => ({ path: "./projstring.js", external: true })) };
await build({ ...common, entryPoints: [path.join(PKG, "src/analysis.ts")], outfile: path.join(DIST, "analysis.js"), plugins: [projstringEntry] });
await build({ ...common, entryPoints: [path.join(PKG, "src/projstring.ts")], outfile: path.join(DIST, "projstring.js") });
await build({ ...common, entryPoints: [path.join(ROOT, "analysis_worker/js/worker.mjs")], outfile: path.join(DIST, "analysis-worker.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/geodesic.ts")], outfile: path.join(DIST, "geodesic.js") });
await build({ ...common, entryPoints: [path.join(ROOT, "geodesic_worker/js/worker.mjs")], outfile: path.join(DIST, "geodesic-worker.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/data.ts")], outfile: path.join(DIST, "data.js"), plugins: [projstringEntry] });
// The zip reader and the CRS conversion stay files of their own, imported by the data worker on first use.
const DATA_PARTS = { "../../npm/src/zip.ts": "data-zip.js", "./crs.mjs": "data-crs.js" };
const dataParts = { name: "data-parts", setup: (b) => b.onResolve({ filter: /^(\.\.\/\.\.\/npm\/src\/zip\.ts|\.\/crs\.mjs)$/ }, (a) => ({ path: `./${DATA_PARTS[a.path]}`, external: true })) };
await build({ ...common, entryPoints: [path.join(ROOT, "data_worker/js/worker.mjs")], outfile: path.join(DIST, "data-worker.js"), plugins: [dataParts] });
for (const [source, file] of Object.entries(DATA_PARTS)) {
  await build({ ...common, entryPoints: [path.join(ROOT, "data_worker/js", source)], outfile: path.join(DIST, file) });
}
// The .prj parser stays a file of its own, imported by the data worker on the first .prj.
await build({ ...common, entryPoints: [path.join(PKG, "src/prjwkt.ts")], outfile: path.join(DIST, "prjwkt.js") });
// The element imports the main entry rather than bundling a second copy of it.
const mainEntry = { name: "main-entry", setup: (b) => b.onResolve({ filter: /^mbmap$/ }, () => ({ path: "./index.js", external: true })) };
await build({ ...common, entryPoints: [path.join(ROOT, "element/element.ts")], outfile: path.join(DIST, "element.js"), plugins: [mainEntry] });
// No wasm-opt: it made the wasm-gc worker slower in every browser (AGENTS.md §4).
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/worker/worker.wasm"), path.join(DIST, "mbmap.wasm"));
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/geojson_worker/geojson_worker.wasm"), path.join(DIST, "geojson.wasm"));
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/geojson_props_worker/geojson_props_worker.wasm"), path.join(DIST, "geojson-properties.wasm"));
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/analysis_worker/analysis_worker.wasm"), path.join(DIST, "analysis.wasm"));
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/geometry_worker/geometry_worker.wasm"), path.join(DIST, "geometry.wasm"));
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/proj_worker/proj_worker.wasm"), path.join(DIST, "proj.wasm"));
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/geodesic_worker/geodesic_worker.wasm"), path.join(DIST, "geodesic.wasm"));
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/data_worker/data_worker.wasm"), path.join(DIST, "data.wasm"));
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/xml_worker/xml_worker.wasm"), path.join(DIST, "xml.wasm"));
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
