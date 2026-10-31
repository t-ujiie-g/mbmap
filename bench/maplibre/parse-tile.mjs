// Bundles parse-tile.ts against maplibre-gl/src with esbuild and runs it.
import { build } from "esbuild";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { ROOT } from "../lib/serve.mjs";

const outfile = path.join(ROOT, "bench/dist/parse-tile.mjs");
await build({
  entryPoints: [path.join(ROOT, "bench/maplibre/parse-tile.ts")],
  bundle: true, platform: "node", format: "esm", target: "node22", outfile,
  minify: true, logLevel: "warning",
  // MapLibre redeclares base-class fields in subclasses; it is built with
  // useDefineForClassFields=false, so the bundle must be too.
  tsconfigRaw: { compilerOptions: { useDefineForClassFields: false } },
  loader: { ".glsl": "text" },
  alias: { "maplibre-src": path.join(ROOT, "bench/node_modules/maplibre-gl/src") },
  banner: { js: "import { createRequire } from 'module'; const require = createRequire(import.meta.url);" },
});
const r = spawnSync(process.execPath, [outfile, ROOT], { stdio: "inherit" });
process.exitCode = r.status;
