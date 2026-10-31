// Analysis bench in Node; writes bench/results/analysis-node.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";
import { nodeFetchBytes } from "../lib/node-io.mjs";
import { makeGeoJSONFixtures } from "../geojson/fixtures.mjs";
import { runAnalysisBench, printAnalysis } from "./bench-core.mjs";

await makeGeoJSONFixtures();
const result = await runAnalysisBench(nodeFetchBytes);
const out = { env: { runtime: `node ${process.version}`, v8: process.versions.v8 }, ...result };
await writeFile(path.join(ROOT, "bench/results/analysis-node.json"), JSON.stringify(out, null, 2) + "\n");
printAnalysis(result);
