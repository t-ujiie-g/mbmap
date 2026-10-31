// Runs the backend comparison in a module Worker in each Playwright browser
// and writes bench/results/backend-<browser>.json.
import { writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { chromium, firefox, webkit } from "playwright";
import { serve, ROOT } from "../lib/serve.mjs";

const { server, origin } = await serve();
await mkdir(path.join(ROOT, "bench/results"), { recursive: true });
const wanted = process.argv.slice(2);
for (const [name, type] of Object.entries({ chromium, firefox, webkit })) {
  if (wanted.length && !wanted.includes(name)) continue;
  const browser = await type.launch();
  const page = await browser.newPage();
  await page.goto(`${origin}/bench/backend/index.html`);
  const result = await page.evaluate(() => window.__result);
  result.env = { ...result.env, browser: name, version: browser.version() };
  await browser.close();
  await writeFile(path.join(ROOT, `bench/results/backend-${name}.json`), JSON.stringify(result, null, 2) + "\n");
  console.log(`\n# ${name} ${result.env.version}`);
  if (result.error) { console.log(result.error); continue; }
  console.table(result.rows.map((r) => ({ name: r.name, ok: r.correct, err: r.error, in: r.in?.median.toFixed(2), decode: r.decode?.median.toFixed(2), out: r.out?.median.toFixed(2), total: r.total?.median.toFixed(2) })));
  console.table(result.alloc.rows.map((r) => ({ name: r.name, ok: r.correct, ms: r.time.median.toFixed(2) })));
}
server.close();
