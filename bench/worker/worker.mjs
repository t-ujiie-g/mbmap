// Worker entry for the browser worker bench; bundled by browser.mjs.
import { loadFixtures, workerFetchBytes } from "../lib/fixtures.mjs";
import { runTileBench } from "./bench-core.mjs";

try {
  const tiles = await loadFixtures(workerFetchBytes);
  postMessage({ env: { userAgent: navigator.userAgent }, ...(await runTileBench(workerFetchBytes, tiles)) });
} catch (err) {
  postMessage({ error: String(err?.stack ?? err) });
}
