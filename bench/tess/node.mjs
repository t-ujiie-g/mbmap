// tess bench in Node; writes bench/results/tess-node.json.
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { ROOT } from "../lib/root.mjs";
import { loadFixtures } from "../lib/fixtures.mjs";
import { nodeFetchBytes, nodeImportJs } from "../lib/node-io.mjs";
import { loadEntry } from "../lib/entry.mjs";
import { runRows, printRows } from "../lib/rows.mjs";
import { tessRows } from "./bench-core.mjs";

const tiles = await loadFixtures(nodeFetchBytes);
const result = await runRows(tiles, tessRows(await loadEntry(nodeFetchBytes, nodeImportJs)));
const out = { env: { runtime: `node ${process.version}`, v8: process.versions.v8 }, ...result };
await writeFile(path.join(ROOT, "bench/results/tess-node.json"), JSON.stringify(out, null, 2) + "\n");
printRows(result);
