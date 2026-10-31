// tess bench in a module Worker per browser; writes bench/results/tess-<browser>.json.
import { runWorkerBench } from "../lib/worker-bench.mjs";

await runWorkerBench({ entry: "bench/tess/worker.mjs", name: "tess" });
