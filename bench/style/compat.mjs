// Reads each public style (style/public-styles.mjs) with the npm build in Chromium, with every
// tile and sprite request refused, and lists what mbmap leaves out of it: its `warning` events.
// node style/compat.mjs [--style=name]
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { serve } from "../lib/serve.mjs";
import { ROOT } from "../lib/root.mjs";
import { layers, namedFlavor } from "@protomaps/basemaps";
import { PUBLIC_STYLES, loadPublicStyle as load } from "./public-styles.mjs";

const only = process.argv.find((a) => a.startsWith("--style="))?.split("=")[1];
const NOWHERE = "https://tiles.invalid";

// Sources as plain `tiles` templates (no TileJSON to wait for) on a host that never answers.
function offline(style) {
  const sources = {};
  for (const [id, s] of Object.entries(style.sources ?? {})) {
    const ext = s.type === "vector" ? "pbf" : "png";
    sources[id] = s.type === "geojson" ? { ...s, data: { type: "FeatureCollection", features: [] } }
      : { ...Object.fromEntries(Object.entries(s).filter(([k]) => k !== "url")), tiles: [`${NOWHERE}/${id}/{z}/{x}/{y}.${ext}`] };
  }
  const { sprite, ...rest } = style;
  return { ...rest, sources };
}

const { server, origin } = await serve();
const browser = await chromium.launch();
const results = {};
try {
  // Protomaps basemaps' styles are generated (5.7.2, the light flavor in Japanese).
  const protomaps = { version: 8, glyphs: "https://glyphs.invalid/{fontstack}/{range}.pbf",
    sources: { protomaps: { type: "vector", tiles: [] } }, layers: layers("protomaps", namedFlavor("light"), { lang: "ja" }) };
  const styles = [...Object.keys(PUBLIC_STYLES).map((name) => [name, () => load(name)]), ["protomaps-light", async () => protomaps]];
  for (const [name, get] of styles) {
    if (only && name !== only) continue;
    const style = offline(await get());
    const page = await browser.newPage();
    await page.route("**/*", (route) => (route.request().url().startsWith(origin) ? route.continue() : route.abort()));
    await page.goto(`${origin}/bench/style/compat.html`);
    results[name] = await page.evaluate(async (style) => {
      const { Map } = await import("/npm/dist/index.js");
      const container = document.createElement("div");
      container.style.cssText = "width:400px;height:300px";
      document.body.append(container);
      let map;
      try {
        map = new Map({ container, style });
      } catch (e) {
        return { error: e.message };
      }
      return await new Promise((resolve) => {
        map.on("warning", (e) => resolve({ warnings: e.warnings }));
        map.on("error", (e) => resolve({ error: String(e.error?.message ?? e.error) }));
        map.on("styledata", () => setTimeout(() => resolve({ warnings: [] }), 500));
      });
    }, style);
    await page.close();
  }
} finally {
  await browser.close();
  server.close();
}

// Warnings by what they are about: the property, expression or layer type, and the styles using it.
const byKind = new globalThis.Map();
for (const [name, r] of Object.entries(results)) {
  if (r.error) console.log(`${name}: refused: ${r.error}`);
  for (const w of r.warnings ?? []) {
    const kind = `${w.path.replace(/^layers\[\d+\]\.?/, "").replace(/\[\d+\]/g, "")}: ${w.message}`;
    const counts = byKind.get(kind) ?? {};
    counts[name] = (counts[name] ?? 0) + 1;
    byKind.set(kind, counts);
  }
}
const rows = [...byKind].map(([kind, counts]) => ({ kind, total: Object.values(counts).reduce((a, b) => a + b, 0), styles: Object.entries(counts).map(([s, n]) => `${s} ${n}`).join(", ") }));
rows.sort((a, b) => b.total - a.total);
console.table(rows);
console.table(Object.entries(results).map(([name, r]) => ({ style: name, warnings: r.warnings?.length ?? "-", refused: r.error ?? "" })));
if (!only) await writeFile(path.join(ROOT, "bench/results/style-compat.json"), `${JSON.stringify({ styles: Object.keys(results), rows, results }, null, 2)}\n`);
