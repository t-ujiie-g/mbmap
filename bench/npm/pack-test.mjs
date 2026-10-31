// Builds and packs npm/, installs the tarball into the examples that use the
// package (examples/npm, examples/element, examples/react) as an app would,
// and checks each in Chromium: the facade's camera, events and error paths,
// <mb-map>'s attributes, events and lifecycle, and <mb-map> driven by React.
// Without the fixtures, tiles 404 and the maps still load (empty), so CI runs
// this too. Usage: node npm/pack-test.mjs [--screenshots=dir]
import { execFileSync } from "node:child_process";
import { mkdir, rm } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";

const run = (cmd, args, cwd) => execFileSync(cmd, args, { cwd, stdio: ["ignore", "pipe", "inherit"] }).toString();
const NPM = path.join(ROOT, "npm");
const OUT = path.join(ROOT, "bench/dist/pack");
const shots = process.argv.find((a) => a.startsWith("--screenshots="))?.split("=")[1];

run("npm", ["run", "-s", "build"], NPM);
await rm(OUT, { recursive: true, force: true });
await mkdir(OUT, { recursive: true });
const [{ filename, files }] = JSON.parse(run("npm", ["pack", "--json", "--pack-destination", OUT], NPM));
console.log(`${filename}: ${files.map((f) => f.path).join(", ")}`);

const install = async (example) => {
  const modules = path.join(ROOT, "examples", example, "node_modules/mbmap");
  await rm(modules, { recursive: true, force: true });
  await mkdir(modules, { recursive: true });
  run("tar", ["xzf", path.join(OUT, filename), "--strip-components=1", "-C", modules], ROOT);
};
await install("npm");
await install("element");
// npm ci empties node_modules, so the tarball goes in afterwards.
run("npm", ["ci", "--no-audit", "--no-fund"], path.join(ROOT, "examples/react"));
await install("react");
run("npm", ["run", "-s", "build"], path.join(ROOT, "examples/react"));

const ATTRIBUTION = "国土地理院ベクトルタイル提供実験";

// Each check runs in a fresh page and returns [name, ok, details].
const checks = {
  async npm(page) {
    const r = await page.evaluate(async () => {
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
      return {
        styleError,
        thrown,
        leftovers: div.children.length,
        center: map.getCenter(),
        zoom: map.getZoom(),
        moves,
        attribution: document.querySelector("#map > div")?.textContent,
        canvas: map.getCanvas().width > 0,
      };
    });
    const ok =
      Math.abs(r.center.lng - 139.7671) < 1e-9 &&
      r.zoom === 15 &&
      r.moves.length === 1 &&
      r.attribution === ATTRIBUTION &&
      r.canvas &&
      r.styleError === "mbmap: style: HTTP 404" &&
      r.thrown === "mbmap: style: layers[0].paint.line-width: unsupported: expression sqrt" &&
      r.leftovers === 0;
    return [ok, r];
  },

  async element(page) {
    const r = await page.evaluate(async () => {
      const el = document.querySelector("mb-map");
      const events = window.__events;
      const before = events.length;
      el.setAttribute("zoom", "15");
      el.setAttribute("zoom", "15");
      el.setAttribute("center", "200,0"); // out of range: rejected
      el.setAttribute("zoom", "1e3"); // not a plain decimal: rejected
      await new Promise((r) => el.addEventListener("mb-idle", r, { once: true }));
      const after = events.slice(before).map((e) => e.type);
      const camera = { center: el.center, zoom: el.zoom };
      // Moving the element keeps its map; detaching it frees the map, and
      // re-attaching creates a new one at the same camera.
      const map = el.map;
      document.body.append(el);
      await Promise.resolve();
      const kept = el.map === map;
      el.remove();
      await Promise.resolve();
      const freed = el.map === null && map.getCanvas().isConnected === false;
      document.body.append(el);
      await new Promise((r) => el.addEventListener("mb-load", r, { once: true }));
      return {
        after,
        camera,
        kept,
        freed,
        recreated: el.map !== null && el.map !== map && el.zoom === 15,
        shadow: el.shadowRoot.querySelectorAll("canvas").length,
        attribution: el.shadowRoot.querySelector("div > div")?.textContent,
        // The attribution is one line in the bottom corner, not an overlay.
        attributionBox: (({ height, bottom }) => ({ height, bottom }))(
          el.shadowRoot.querySelector("div > div").getBoundingClientRect(),
        ),
      };
    });
    const ok =
      r.after.filter((t) => t === "mb-move").length === 1 &&
      r.after.filter((t) => t === "mb-error").length === 2 &&
      r.camera.zoom === 15 &&
      Math.abs(r.camera.center.lng - 139.7671) < 1e-9 &&
      r.kept &&
      r.freed &&
      r.recreated &&
      r.shadow === 1 &&
      r.attribution === ATTRIBUTION &&
      r.attributionBox.height < 40 &&
      r.attributionBox.bottom === 600;
    return [ok, r];
  },

  async react(page) {
    await page.click("button >> text=+");
    await page.waitForFunction(() => document.querySelector("output").textContent === "15.50");
    const read = () =>
      page.evaluate(() => {
        const el = document.querySelector("mb-map");
        return { zoom: el.zoom, output: document.querySelector("output").textContent, maps: document.querySelectorAll("mb-map").length };
      });
    const clicked = await read();
    // A wheel zoom inside the map reaches React only through onmb-move.
    await page.mouse.move(400, 300);
    await page.mouse.wheel(0, 200);
    await page.waitForFunction(() => document.querySelector("output").textContent !== "15.50");
    const wheeled = await read();
    const ok =
      clicked.zoom === 15.5 &&
      clicked.maps === 1 &&
      wheeled.zoom < 15.5 &&
      wheeled.output === wheeled.zoom.toFixed(2);
    return [ok, { clicked, wheeled }];
  },
};

const { server, origin } = await serve();
// Metal only exists on macOS; elsewhere (CI) Chromium falls back to SwiftShader.
const gpu = process.platform === "darwin" ? ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] : [];
const browser = await chromium.launch({ args: gpu });
let failed = false;
try {
  for (const [example, check] of Object.entries(checks)) {
    const page = await browser.newPage({ viewport: { width: 800, height: 600 } });
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    // 404s are expected (missing style, missing fixtures); so are the
    // rejections the element check provokes.
    page.on("console", (m) => m.type() === "error" && !/404|mb-map: invalid/.test(m.text()) && errors.push(m.text()));
    await page.goto(`${origin}/examples/${example}/`);
    await page.waitForFunction(() => window.__loaded, null, { timeout: 30000 });
    if (shots) await page.screenshot({ path: path.join(shots, `${example}.png`) });
    const [ok, details] = await check(page);
    const pass = ok && errors.length === 0;
    failed ||= !pass;
    console.log(`${pass ? "ok  " : "FAIL"} ${example} ${JSON.stringify({ ...details, errors })}`);
    await page.close();
  }
} finally {
  await browser.close();
  server.close();
}
if (failed) process.exit(1);
console.log("pack test passed");
