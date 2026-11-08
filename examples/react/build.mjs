// Bundles the app with esbuild, which leaves `new URL("./worker.js", import.meta.url)` alone,
// so the workers and wasm are copied next to the bundle; the shared modules resolve `mbmap`
// from this example's node_modules.
import { copyFile, mkdir, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const DIR = path.dirname(fileURLToPath(import.meta.url));
const DIST = path.join(DIR, "dist");
const PACKAGE = path.join(DIR, "node_modules/mbmap/dist");
await mkdir(DIST, { recursive: true });
await build({
  entryPoints: [path.join(DIR, "src/main.jsx")],
  outfile: path.join(DIST, "app.js"),
  bundle: true,
  minify: true,
  format: "esm",
  jsx: "automatic",
  nodePaths: [path.join(DIR, "node_modules")],
  define: { "process.env.NODE_ENV": '"production"' },
  logLevel: "warning",
});
for (const f of await readdir(PACKAGE)) {
  if (f.endsWith(".wasm") || /(worker(-\w+)?|data-\w+|analysis-\w+|prjwkt|projstring)\.js$/.test(f)) await copyFile(path.join(PACKAGE, f), path.join(DIST, f));
}
