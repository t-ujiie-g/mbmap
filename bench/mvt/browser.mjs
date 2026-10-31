// mvt decode bench in a module Worker per browser; writes bench/results/mvt-decode-<browser>.json.
import { runWorkerBench } from "../lib/worker-bench.mjs";

await runWorkerBench({ entry: "bench/mvt/worker.mjs", name: "mvt-decode" });
