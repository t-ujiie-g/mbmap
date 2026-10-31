// Builds and packs npm/, installs the tarball into examples/npm/node_modules
// as an app would, and checks in Chromium that the example loads and that
// the facade's camera and events work. Without the fixtures, tiles 404 and
// the map still loads (empty), so CI runs this too.
// Usage: node npm/pack-test.mjs [--screenshot=path.png]
import { execFileSync } from "node:child_process";
import { mkdir, rm } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";

const run = (cmd, args, cwd) => execFileSync(cmd, args, { cwd, stdio: ["ignore", "pipe", "inherit"] }).toString();
const NPM = path.join(ROOT, "npm");
const OUT = path.join(ROOT, "bench/dist/pack");
const MODULES = path.join(ROOT, "examples/npm/node_modules/mbmap");

run("npm", ["run", "-s", "build"], NPM);
await rm(OUT, { recursive: true, force: true });
await mkdir(OUT, { recursive: true });
const [{ filename, files }] = JSON.parse(run("npm", ["pack", "--json", "--pack-destination", OUT], NPM));
console.log(`${filename}: ${files.map((f) => f.path).join(", ")}`);
await rm(MODULES, { recursive: true, force: true });
await mkdir(MODULES, { recursive: true });
run("tar", ["xzf", path.join(OUT, filename), "--strip-components=1", "-C", MODULES], ROOT);

const { server, origin } = await serve();
// Metal only exists on macOS; elsewhere (CI) Chromium falls back to SwiftShader.
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
const errors = [];
page.on("pageerror", (e) => errors.push(e.message));
page.on("console", (m) => m.type() === "error" && errors.push(m.text()));
try {
  await page.goto(`${origin}/examples/npm/`);
  await page.waitForFunction(() => window.__loaded, null, { timeout: 30000 });
  const result = await page.evaluate(async () => {
    const map = window.__map;
    const moves = [];
    map.on("move", () => moves.push(map.getZoom()));
    map.jumpTo({ zoom: 15 });
    map.jumpTo({ zoom: 15 });
    await map.once("idle");
    // Error paths: a style URL that fails fires `error`; a bad style object throws.
    const { Map } = await import("mbmap");
    const div = document.createElement("div");
    div.style.cssText = "width:10px;height:10px";
    document.body.append(div);
    const missing = new Map({ container: div, style: "/examples/npm/missing.json" });
    const styleError = (await missing.once("error")).error.message;
    missing.remove();
    let thrown = "";
    try {
      new Map({ container: div, style: { version: 8, sources: {}, layers: [{ id: "x", type: "line", paint: { "line-width": ["sqrt", 2] } }] } });
    } catch (e) {
      thrown = e.message;
    }
    const leftovers = div.children.length;
    return {
      styleError,
      thrown,
      leftovers,
      center: map.getCenter(),
      zoom: map.getZoom(),
      moves,
      attribution: document.querySelector("#map > div")?.textContent,
      canvas: map.getCanvas().width > 0,
    };
  });
  const arg = process.argv.find((a) => a.startsWith("--screenshot="));
  if (arg) await page.screenshot({ path: arg.split("=")[1] });
  console.log(JSON.stringify(result));
  const ok =
    Math.abs(result.center.lng - 139.7671) < 1e-9 &&
    result.zoom === 15 &&
    result.moves.length === 1 &&
    result.attribution === "国土地理院ベクトルタイル提供実験" &&
    result.canvas &&
    result.styleError === "mbmap: style: HTTP 404" &&
    result.thrown === "mbmap: style: layers[0].paint.line-width: unsupported: expression sqrt" &&
    result.leftovers === 0 &&
    errors.filter((e) => !e.includes("404")).length === 0;
  if (!ok) throw new Error(`pack test failed: ${JSON.stringify({ result, errors })}`);
  console.log("pack test passed");
} finally {
  await browser.close();
  server.close();
}
