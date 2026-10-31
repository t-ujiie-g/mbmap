// Bundles parse-tile.ts against maplibre-gl/src and runs it.
import { spawnSync } from "node:child_process";
import path from "node:path";
import { bundle } from "../lib/bundle.mjs";
import { ROOT } from "../lib/root.mjs";

const outfile = "bench/dist/parse-tile.mjs";
await bundle("bench/maplibre/parse-tile.ts", outfile, { platform: "node" });
const r = spawnSync(process.execPath, [path.join(ROOT, outfile), ROOT], { stdio: "inherit" });
process.exitCode = r.status;
