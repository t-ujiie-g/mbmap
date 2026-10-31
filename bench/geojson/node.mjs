// GeoJSON bench in Node; writes bench/results/geojson-node.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { loadEntry } from "../lib/entry.mjs";
import { makeGeoJSONFixtures } from "./fixtures.mjs";
import { runGeoJSONBench, printGeoJSON } from "./bench-core.mjs";

await makeGeoJSONFixtures();
const result = await runGeoJSONBench(nodeFetchBytes, await loadEntry(nodeFetchBytes, nodeImportJs));
const out = { env: { runtime: `node ${process.version}`, v8: process.versions.v8 }, ...result };
await writeFile(path.join(ROOT, "bench/results/geojson-node.json"), JSON.stringify(out, null, 2) + "\n");
printGeoJSON(result);
