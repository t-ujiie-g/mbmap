// Worker bench in a module Worker per browser; writes bench/results/worker-<browser>.json.
import { runWorkerBench as runInBrowsers } from "../lib/worker-bench.mjs";

await runInBrowsers({ entry: "bench/worker/worker.mjs", name: "worker" });
