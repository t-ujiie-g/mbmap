// mbmap/analysis's classBreaks and statistics (npm/src/classify.ts, TypeScript on the main thread) vs
// simple-statistics 8.0.0 and geostats 2.1.0 on classify:golden's kinds of values, larger.
// Usage: node --experimental-strip-types classify/node.mjs; writes bench/results/classify-node.json.
import * as ss from "simple-statistics";
import geostats from "geostats";
import { classBreaks, statistics } from "../../npm/src/classify.ts";
import { gsiTiles, rng, rows, time, TIMING, writeResults } from "../lib/analysis-modules.mjs";

const { all, row } = rows();
const rand = rng(193);
const randoms = (n) => Array.from({ length: n }, () => (rand() - 0.3) * 10 ** (rand() * 6));

// Every numeric attribute of the GSI tiles' features, one array.
const gsi = [];
for (const t of await gsiTiles(6)) for (const name of t.names()) for (const p of t.properties(name)) for (const v of Object.values(p)) if (typeof v === "number") gsi.push(v);

const sets = [["random", randoms(1000)], ["random", randoms(100000)], ["random", randoms(1000000)], ["gsi attributes", gsi]];
for (const [name, x] of sets) {
  const label = `${name} ${x.length}`;
  const n = 7;
  row(`statistics (${label})`, time(() => [ss.min(x), ss.max(x), ss.sum(x), ss.mean(x), ss.median(x), ss.variance(x), ss.standardDeviation(x)]), time(() => statistics(x)));
  row(`quantile ${n} classes (${label})`, time(() => ss.quantile(x, Array.from({ length: n + 1 }, (_, i) => i / n))), time(() => classBreaks(x, n, "quantile")));
  row(`equalInterval ${n} classes (${label})`, time(() => ss.equalIntervalBreaks(x, n)), time(() => classBreaks(x, n, "equalInterval")));
  row(`standardDeviation ${n} classes (${label}; JS: geostats)`, time(() => new geostats(x).getClassStdDeviation(n)), time(() => classBreaks(x, n, "standardDeviation")));
  if (x.length <= 100000) row(`ckmeans ${n} classes (${label})`, time(() => ss.ckmeans(x, n).map((c) => c[0]).concat([ss.max(x)])), time(() => classBreaks(x, n, "ckmeans")));
  if (x.length <= 2000) row(`jenks ${n} classes (${label})`, time(() => ss.jenks(x, n)), time(() => classBreaks(x, n, "jenks")));
}
const jenksSet = randoms(5000);
row("jenks 7 classes (random 5000)", time(() => ss.jenks(jenksSet, 7)), time(() => classBreaks(jenksSet, 7, "jenks")));

await writeResults("classify-node", { simpleStatistics: "8.0.0", geostats: "2.1.0", statistic: TIMING, columns: "both JavaScript: mbmap's classify.ts copies the finite values into a Float64Array on every call" }, all);
