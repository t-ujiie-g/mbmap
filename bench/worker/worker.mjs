// Worker entry for the browser worker bench; bundled by browser.mjs.
import { loadFixtures, workerFetchBytes } from "../lib/fixtures.mjs";
import { runWorkerBench } from "./bench-core.mjs";

try {
  const tiles = await loadFixtures(workerFetchBytes);
  postMessage({ env: { userAgent: navigator.userAgent }, ...(await runWorkerBench(workerFetchBytes, tiles)) });
} catch (err) {
  postMessage({ error: String(err?.stack ?? err) });
}
