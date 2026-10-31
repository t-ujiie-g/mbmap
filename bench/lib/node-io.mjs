// Node implementations of the host hooks used by lib/fixtures.mjs and lib/entry.mjs.
import { readFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { ROOT } from "./root.mjs";

export const nodeFetchBytes = async (rel) => new Uint8Array(await readFile(path.join(ROOT, rel)));

export const nodeImportJs = (rel) => import(pathToFileURL(path.join(ROOT, rel)).href);
