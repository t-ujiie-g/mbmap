// Worker entry for the browser analysis bench; bundled by browser.mjs.
import { workerFetchBytes } from "../lib/fixtures.mjs";
import { runAnalysisBench } from "./bench-core.mjs";

try {
  const result = await runAnalysisBench(workerFetchBytes);
  postMessage({ env: { userAgent: navigator.userAgent }, ...result });
} catch (err) {
  postMessage({ error: String(err?.stack ?? err) });
}
