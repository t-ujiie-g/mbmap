// esbuild settings shared by every bench bundle. `maplibre-src` resolves to
// MapLibre's TypeScript sources so benches can call WorkerTile.parse directly.
import { build } from "esbuild";
import path from "node:path";
import { ROOT } from "./root.mjs";

// MapLibre redeclares base-class fields in subclasses; it is built with
// useDefineForClassFields=false, so the bundle must be too.
export async function bundle(entry, outfile, { platform }) {
  await build({
    entryPoints: [path.join(ROOT, entry)],
    bundle: true, format: "esm", platform, outfile: path.join(ROOT, outfile),
    target: platform === "node" ? "node22" : "es2022",
    minify: true, logLevel: "warning",
    external: ["/_build/*"],
    tsconfigRaw: { compilerOptions: { useDefineForClassFields: false } },
    loader: { ".glsl": "text" },
    alias: { "maplibre-src": path.join(ROOT, "bench/node_modules/maplibre-gl/src") },
    banner: platform === "node"
      ? { js: "import { createRequire } from 'module'; const require = createRequire(import.meta.url);" }
      : undefined,
  });
}
