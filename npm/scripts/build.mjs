// Builds dist/: the facade, `<mb-map>`, the GeoJSON and analysis modules and
// their workers with their wasm. Usage: node scripts/build.mjs
import { execFileSync } from "node:child_process";
import { copyFile, mkdir, rm } from "node:fs/promises";
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
run("moon", ["build", "analysis_worker", "--target", "wasm-gc", "--release"], ROOT);
await rm(DIST, { recursive: true, force: true });
await mkdir(DIST);

const common = { bundle: true, minify: true, format: "esm", target: "es2022", logLevel: "warning", legalComments: "none" };
// The GeoJSON module stays a file of its own, loaded only by maps that need it.
const geojsonEntry = { name: "geojson-entry", setup: (b) => b.onResolve({ filter: /^\.\/geojson\.js$/ }, () => ({ path: "./geojson.js", external: true })) };
await build({
  ...common,
  entryPoints: [path.join(PKG, "src/index.ts")],
  outfile: path.join(DIST, "index.js"),
  alias: { "mbmap-engine": path.join(ROOT, "_build/js/release/build/bundle/main/main.js") },
  plugins: [geojsonEntry],
});
await build({ ...common, entryPoints: [path.join(PKG, "src/geojson.ts")], outfile: path.join(DIST, "geojson.js") });
await build({ ...common, entryPoints: [path.join(ROOT, "geojson_worker/js/worker.mjs")], outfile: path.join(DIST, "geojson-worker.js") });
await build({ ...common, entryPoints: [path.join(ROOT, "worker/js/worker.mjs")], outfile: path.join(DIST, "worker.js") });
await build({ ...common, entryPoints: [path.join(PKG, "src/analysis.ts")], outfile: path.join(DIST, "analysis.js") });
await build({ ...common, entryPoints: [path.join(ROOT, "analysis_worker/js/worker.mjs")], outfile: path.join(DIST, "analysis-worker.js") });
// The element imports the main entry rather than bundling a second copy of it.
const mainEntry = { name: "main-entry", setup: (b) => b.onResolve({ filter: /^mbmap$/ }, () => ({ path: "./index.js", external: true })) };
await build({ ...common, entryPoints: [path.join(ROOT, "element/element.ts")], outfile: path.join(DIST, "element.js"), plugins: [mainEntry] });
// No wasm-opt: it made the wasm-gc worker slower in every browser (AGENTS.md §4).
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/worker/worker.wasm"), path.join(DIST, "mbmap.wasm"));
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/geojson_worker/geojson_worker.wasm"), path.join(DIST, "geojson.wasm"));
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/analysis_worker/analysis_worker.wasm"), path.join(DIST, "analysis.wasm"));
const tsc = path.join(PKG, "node_modules/typescript/bin/tsc");
run(process.execPath, [tsc, "-p", path.join(PKG, "tsconfig.json")], PKG);
run(process.execPath, [tsc, "-p", path.join(ROOT, "element/tsconfig.json")], PKG);
for (const f of ["LICENSE", "NOTICE"]) await copyFile(path.join(ROOT, f), path.join(PKG, f));
