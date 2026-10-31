// Runs the backend comparison inside a module Worker, like the real engine.
import { loadModules } from "./load.mjs";
import { runSuite, runAllocSuite } from "./harness.mjs";

try {
  const { modules, load } = await loadModules({
    fetchBytes: async (rel) => new Uint8Array(await (await fetch(`/${rel}`)).arrayBuffer()),
    importJs: (rel) => import(`/${rel}`),
  });
  postMessage({ env: { userAgent: navigator.userAgent, crossOriginIsolated }, load, ...runSuite(modules), alloc: runAllocSuite(modules) });
} catch (err) {
  postMessage({ error: String(err?.stack ?? err) });
}
