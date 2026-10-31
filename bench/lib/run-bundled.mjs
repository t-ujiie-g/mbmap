// Bundles a Node bench entry (which may import TypeScript / MapLibre sources) and runs it.
// Usage: node lib/run-bundled.mjs bench/<dir>/<entry>.mjs [args...]
import { spawnSync } from "node:child_process";
import path from "node:path";
import { bundle } from "./bundle.mjs";
import { ROOT } from "./root.mjs";

const [entry, ...args] = process.argv.slice(2);
const outfile = `bench/dist/${entry.replaceAll("/", "_").replace(/\.(mjs|ts)$/, "")}.mjs`;
await bundle(entry, outfile, { platform: "node" });
const r = spawnSync(process.execPath, [path.join(ROOT, outfile), ...args], { stdio: "inherit" });
process.exitCode = r.status;
