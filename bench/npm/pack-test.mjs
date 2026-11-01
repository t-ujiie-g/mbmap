// Checks the examples built on the packed package in Chromium; without the
// fixtures tiles 404 and maps load empty, so CI runs it too.
// Usage: node npm/pack-test.mjs [--screenshots=dir]
import path from "node:path";
import { chromium } from "playwright";
import { serve } from "../lib/serve.mjs";
import { prepareExamples } from "./prepare.mjs";

const shots = process.argv.find((a) => a.startsWith("--screenshots="))?.split("=")[1];
await prepareExamples();

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
      map.jumpTo({ bearing: 370, pitch: 75 });
      const turned = { bearing: map.getBearing(), pitch: map.getPitch() };
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
      let workerRefused = "";
      try {
        new Map({ container: div, style: { version: 8, sources: {}, layers: [] }, workerUrl: "data:text/javascript,1" });
      } catch (e) {
        workerRefused = e.message;
      }
      const loaded = performance.getEntriesByType("resource").map((r) => r.name.split("/").pop());
      return {
        // A style without GeoJSON sources never loads their module.
        lazy: !loaded.some((n) => n.startsWith("geojson") || n.startsWith("analysis")),
        styleError,
        thrown,
        workerRefused,
        leftovers: div.children.length,
        center: map.getCenter(),
        zoom: map.getZoom(),
        moves,
        turned,
        attribution: document.querySelector("#map > div")?.textContent,
        canvas: map.getCanvas().width > 0,
      };
    });
    const ok =
      Math.abs(r.center.lng - 139.7671) < 1e-9 &&
      r.zoom === 15 &&
      r.moves.length === 2 &&
      // Bearing wraps and pitch is clamped to 60.
      Math.abs(r.turned.bearing - 10) < 1e-9 &&
      r.turned.pitch === 60 &&
      r.attribution === ATTRIBUTION &&
      r.canvas &&
      r.styleError === "mbmap: style: HTTP 404" &&
      r.thrown === "mbmap: style: layers[0].paint.line-width: unsupported: expression sqrt" &&
      r.lazy &&
      r.workerRefused.startsWith("mbmap: the worker must be a same-origin http(s) URL") &&
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
      el.setAttribute("pitch", "61"); // above MAX_PITCH: rejected
      await new Promise((r) => el.addEventListener("mb-idle", r, { once: true }));
      const after = events.slice(before).map((e) => e.type);
      const camera = { center: el.center, zoom: el.zoom };
      el.setAttribute("pitch", "45");
      el.setAttribute("bearing", "-30");
      const tilted = { pitch: el.pitch, bearing: el.bearing };
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
        tilted,
        kept,
        freed,
        recreated: el.map !== null && el.map !== map && el.zoom === 15 && el.pitch === 45,
        shadow: el.shadowRoot.querySelectorAll("canvas").length,
        attribution: el.shadowRoot.querySelector("div > div")?.textContent,
        // The attribution is one line in the bottom corner, not an overlay.
        attributionBox: (({ height, bottom }) => ({ height, bottom }))(
          el.shadowRoot.querySelector("div > div").getBoundingClientRect(),
        ),
      };
    });
    // A right-button drag turns the map (horizontal) and tilts it (vertical).
    const before = await page.evaluate(() => ({ bearing: document.querySelector("mb-map").bearing, pitch: document.querySelector("mb-map").pitch }));
    await page.mouse.move(400, 300);
    await page.mouse.down({ button: "right" });
    await page.mouse.move(500, 260, { steps: 5 });
    await page.mouse.up({ button: "right" });
    const after = await page.evaluate(() => ({ bearing: document.querySelector("mb-map").bearing, pitch: document.querySelector("mb-map").pitch }));
    r.dragged = { before, after };
    const turn = ((after.bearing - before.bearing + 540) % 360) - 180;
    const ok =
      Math.abs(turn + 80) < 1e-6 &&
      Math.abs(after.pitch - Math.min(60, before.pitch + 20)) < 1e-6 &&
      r.after.filter((t) => t === "mb-move").length === 1 &&
      r.after.filter((t) => t === "mb-error").length === 3 &&
      r.tilted.pitch === 45 &&
      r.tilted.bearing === -30 &&
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

  async geojson(page, requests) {
    const r = await page.evaluate(async () => {
      const map = window.__map;
      // Tilting re-requests tiles at lower zooms in the distance, from the
      // GeoJSON worker too.
      map.jumpTo({ pitch: 50 });
      await map.once("idle");
      return { pitch: map.getPitch() };
    });
    // The worker fetches the wasm and the URL source; the page the module.
    const loaded = requests.map((u) => u.split("/").pop()).filter((n) => /geojson/.test(n));
    const ok = ["geojson.js", "geojson-worker.js", "geojson.wasm", "places.geojson"].every((n) => loaded.includes(n)) && r.pitch === 50;
    return [ok, { loaded, pitch: r.pitch }];
  },

  async analysis(page, requests) {
    const r = await page.evaluate(async () => {
      const { load, distance } = await import("mbmap/analysis");
      // A disposed dataset rejects; a non-http URL is refused before any request.
      const d = await load({ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [0, 0] } });
      d.dispose();
      const disposed = await d.areas().then(() => "", (e) => e.message);
      const refused = await load("data:application/json,{}").then(() => "", (e) => e.message);
      const malformed = await load(new TextEncoder().encode("{\"type\": ")).then(() => "", (e) => e.message);
      // A DEM grid of the Mt Fuji fixtures (tiles 404 without them: 0 m).
      const { loadDem } = await import("mbmap/analysis");
      const dem = await loadDem("/bench/fixtures/gsi-dem-fuji/{z}/{x}/{y}.png", { zoom: 12, bounds: [138.6, 35.25, 138.85, 35.45], encoding: "gsi" });
      const slope = await dem.slope();
      const shade = await dem.hillshade();
      const grid = { width: dem.width, height: dem.height, slopes: slope.length, shades: shade.length, west: Math.round(dem.bounds[0] * 1000) / 1000 };
      dem.dispose();
      return { ...window.__analysis, disposed, refused, malformed, grid, tokyoLondon: Math.round(distance([139.7671, 35.6812], [-0.1276, 51.5072])) };
    });
    const loaded = requests.map((u) => u.split("/").pop()).filter((n) => /analysis/.test(n));
    const ok =
      ["analysis.js", "analysis-worker.js", "analysis.wasm"].every((n) => loaded.includes(n)) &&
      r.areas.length === 6 &&
      r.areas.every((a) => a > 90000 && a < 120000) &&
      r.count.reduce((a, b) => a + b, 0) === r.inside &&
      r.inside > 300 &&
      /disposed/.test(r.disposed) &&
      /http\(s\) URL/.test(r.refused) &&
      /malformed GeoJSON/.test(r.malformed) &&
      r.tokyoLondon === 9562323 &&
      // Tiles 3624-3627 x 1617-1619 at z12: 4 x 3 of 256 cells.
      r.grid.width === 1024 && r.grid.height === 768 &&
      r.grid.slopes === 1024 * 768 && r.grid.shades === 1024 * 768 &&
      r.grid.west === 138.516;
    return [ok, { loaded, ...r }];
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
    const requests = [];
    page.on("request", (r) => requests.push(r.url()));
    page.on("pageerror", (e) => errors.push(e.message));
    // 404s are expected (missing style, missing fixtures); so are the
    // rejections the element check provokes.
    page.on("console", (m) => m.type() === "error" && !/404|mb-map: invalid/.test(m.text()) && errors.push(m.text()));
    await page.goto(`${origin}/examples/${example}/`);
    await page.waitForFunction(() => window.__loaded, null, { timeout: 30000 });
    if (shots) await page.screenshot({ path: path.join(shots, `${example}.png`) });
    const [ok, details] = await check(page, requests);
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
