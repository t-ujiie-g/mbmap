// Bundles the app with esbuild, a bundler that leaves
// `new URL("./worker.js", import.meta.url)` alone: the URL then points next
// to the bundle, so the worker and its wasm are copied there.
import { copyFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const DIST = path.join(DIR, "dist");
await mkdir(DIST, { recursive: true });
await build({
  entryPoints: [path.join(DIR, "src/main.jsx")],
  outfile: path.join(DIST, "app.js"),
  bundle: true,
  minify: true,
  format: "esm",
  jsx: "automatic",
  define: { "process.env.NODE_ENV": '"production"' },
  logLevel: "warning",
});
for (const f of ["worker.js", "mbmap.wasm"]) {
  await copyFile(path.join(DIR, "node_modules/mbmap/dist", f), path.join(DIST, f));
}
