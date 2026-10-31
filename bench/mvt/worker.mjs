// Worker entry for the browser mvt decode bench; bundled by browser.mjs.
import { loadFixtures, workerFetchBytes } from "../lib/fixtures.mjs";
import { loadEntry, workerImportJs } from "../lib/entry.mjs";
import { runRows } from "../lib/rows.mjs";
import { mvtRows } from "./bench-core.mjs";

try {
  const tiles = await loadFixtures(workerFetchBytes);
  const rows = mvtRows(await loadEntry(workerFetchBytes, workerImportJs));
  postMessage({ env: { userAgent: navigator.userAgent, crossOriginIsolated }, ...(await runRows(tiles, rows)) });
} catch (err) {
  postMessage({ error: String(err?.stack ?? err) });
}
