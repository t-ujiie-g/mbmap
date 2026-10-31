// Worker entry for the browser GeoJSON bench; bundled by browser.mjs.
import { workerFetchBytes } from "../lib/fixtures.mjs";
import { loadEntry, workerImportJs } from "../lib/entry.mjs";
import { runGeoJSONBench } from "./bench-core.mjs";

try {
  const result = await runGeoJSONBench(workerFetchBytes, await loadEntry(workerFetchBytes, workerImportJs));
  postMessage({ env: { userAgent: navigator.userAgent }, ...result });
} catch (err) {
  postMessage({ error: String(err?.stack ?? err) });
}
