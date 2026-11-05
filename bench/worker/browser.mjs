// Worker bench in a module Worker per browser; writes bench/results/worker-<browser>.json.
import { runWorkerBench } from "../lib/worker-bench.mjs";

await runWorkerBench({ entry: "bench/worker/worker.mjs", name: "worker" });
