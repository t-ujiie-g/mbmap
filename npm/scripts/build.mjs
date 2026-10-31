// Builds the package into dist/: the MoonBit main-thread build wrapped by the
// TS facade (index.js + index.d.ts), the worker glue (worker.js) and the
// wasm-gc worker (mbmap.wasm). Usage: node scripts/build.mjs
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
await rm(DIST, { recursive: true, force: true });
await mkdir(DIST);

const common = { bundle: true, minify: true, format: "esm", target: "es2022", logLevel: "warning", legalComments: "none" };
await build({
  ...common,
  entryPoints: [path.join(PKG, "src/index.ts")],
  outfile: path.join(DIST, "index.js"),
  alias: { "mbmap-engine": path.join(ROOT, "_build/js/release/build/bundle/main/main.js") },
});
await build({ ...common, entryPoints: [path.join(ROOT, "worker/js/worker.mjs")], outfile: path.join(DIST, "worker.js") });
// No wasm-opt: it made the wasm-gc worker slower in every browser (AGENTS.md §4).
await copyFile(path.join(ROOT, "_build/wasm-gc/release/build/worker/worker.wasm"), path.join(DIST, "mbmap.wasm"));
run(process.execPath, [path.join(PKG, "node_modules/typescript/bin/tsc"), "-p", path.join(PKG, "tsconfig.json")], PKG);
for (const f of ["LICENSE", "NOTICE"]) await copyFile(path.join(ROOT, f), path.join(PKG, f));
