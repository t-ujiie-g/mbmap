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
      map.jumpTo({ bearing: 370, pitch: 89 });
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
      // `lazy`: a style without GeoJSON sources never loads their module.
      const loaded = performance.getEntriesByType("resource").map((r) => r.name.split("/").pop());
      return {
        lazy: !loaded.some((n) => n.startsWith("geojson") || n.startsWith("analysis") || n.startsWith("geometry") || n.startsWith("proj")),
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
      // Bearing wraps and pitch is clamped to 85.
      Math.abs(r.turned.bearing - 10) < 1e-9 &&
      r.turned.pitch === 85 &&
      r.attribution === ATTRIBUTION &&
      r.canvas &&
      r.styleError === "mbmap: style: HTTP 404" &&
      r.thrown === "mbmap: style: layers[0].paint.line-width: unsupported: expression sqrt" &&
      r.lazy &&
      r.workerRefused.startsWith("mbmap: the worker must be a same-origin http(s) URL") &&
      r.leftovers === 0;
    const camera = await cameraChecks(page);
    return [ok && camera.ok, { ...r, camera }];
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
      el.setAttribute("pitch", "86"); // above MAX_PITCH: rejected
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
      // `attributionBox`: the attribution is one line in the bottom corner, not an overlay.
      return {
        after,
        camera,
        tilted,
        kept,
        freed,
        recreated: el.map !== null && el.map !== map && el.zoom === 15 && el.pitch === 45,
        shadow: el.shadowRoot.querySelectorAll("canvas").length,
        attribution: el.shadowRoot.querySelector("div > div")?.textContent,
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
      Math.abs(after.pitch - Math.min(85, before.pitch + 20)) < 1e-6 &&
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
      // Geometry operations (geometry.wasm, loaded now): a 500 m circle, a line
      // cut by a square, two squares merged, erased and overlaid.
      const sq = (x, name) => ({ type: "Feature", properties: { name }, geometry: { type: "Polygon", coordinates: [[[x, 0], [x + 1, 0], [x + 1, 1], [x, 1], [x, 0]]] } });
      const fc = (features) => ({ type: "FeatureCollection", features });
      const pt = await load({ type: "Feature", properties: { id: 1 }, geometry: { type: "Point", coordinates: [139.7, 35.7] } });
      const circle = (await (await pt.buffer(500)).toGeoJSON()).features[0];
      const line = await load(fc([{ type: "Feature", properties: { name: "l" }, geometry: { type: "LineString", coordinates: [[-1, 0.5], [2, 0.5]] } }]));
      const squares = await load(fc([sq(0, "a"), sq(0.5, "b")]));
      const clipped = (await (await line.clip(squares)).toGeoJSON()).features[0];
      const merged = (await (await squares.dissolve()).toGeoJSON()).features;
      const erased = (await (await squares.erase(await load(fc([sq(0.5, "c")])))).toGeoJSON()).features;
      const overlaid = (await (await squares.intersect(await load(fc([sq(0.5, "c")])))).toGeoJSON()).features;
      const badBuffer = await pt.buffer(NaN).then(() => "", (e) => e.message);
      // Coordinate systems: Tokyo Station in plane rectangular IX (EPSG:6677).
      const { transform } = await import("mbmap/analysis");
      const ix = await transform([139.7671, 35.6812], "EPSG:4326", "EPSG:6677");
      const station = await load({ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [ix[0], ix[1]] } }, { crs: 6677 });
      const back = (await station.toGeoJSON()).features[0].geometry.coordinates;
      const inIx = (await station.toGeoJSON({ crs: "urn:ogc:def:crs:EPSG::6677" })).features[0].geometry.coordinates;
      const ring = (await (await station.buffer(100, { mode: "planar", crs: 6677 })).toGeoJSON({ crs: 6677 })).features[0].geometry.coordinates[0];
      const planarRadius = Math.max(...ring.map(([x, y]) => Math.abs(Math.hypot(x - ix[0], y - ix[1]) - 100)));
      const unknownCrs = await transform([0, 0], 4326, 9999).then(() => "", (e) => e.message);
      // A PROJ string (Lambert 93, loading the parser), a named one, the Tokyo datum.
      const { defineCrs } = await import("mbmap/analysis");
      const lambert = "+proj=lcc +lat_0=46.5 +lon_0=3 +lat_1=49 +lat_2=44 +x_0=700000 +y_0=6600000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs";
      const paris = await transform([2.3522, 48.8566], 4326, lambert);
      defineCrs("EPSG:2154", lambert);
      const named = await transform([2.3522, 48.8566], "CRS84", "epsg:2154");
      const tokyoDatum = await transform([139.7671, 35.6812], 4326, 30169);
      const badProj = await transform([0, 0], 4326, "+proj=geos +h=35785831").then(() => "", (e) => e.message);
      const geometry = {
        circle: [circle.geometry.type, circle.geometry.coordinates[0].length, circle.properties.id],
        clipped: [clipped.geometry.type, clipped.geometry.coordinates, clipped.properties.name],
        merged: [merged.length, merged[0].geometry.coordinates[0].length],
        erased: erased.map((f) => f.properties.name),
        overlaid: overlaid.map((f) => `${f.properties.name}/${f.properties.name_2}`),
        badBuffer,
        ix: [Math.round(ix[0] * 1000) / 1000, Math.round(ix[1] * 1000) / 1000],
        back: back.map((v) => Math.round(v * 1e7) / 1e7),
        inIx: inIx.map((v) => Math.round(v * 1000) / 1000),
        planarRadius,
        unknownCrs,
        paris: Array.from(paris, (v) => Math.round(v * 1000) / 1000),
        named: Array.from(named, (v) => Math.round(v * 1000) / 1000),
        tokyoDatum: Array.from(tokyoDatum, (v) => Math.round(v * 1000) / 1000),
        badProj,
      };
      return { ...window.__analysis, disposed, refused, malformed, grid, geometry, tokyoLondon: Math.round(distance([139.7671, 35.6812], [-0.1276, 51.5072])) };
    });
    const loaded = requests.map((u) => u.split("/").pop()).filter((n) => /analysis|geometry|proj/.test(n));
    const ok =
      ["analysis.js", "analysis-worker.js", "analysis.wasm", "geometry.wasm", "proj.wasm", "projstring.js"].every((n) => loaded.includes(n)) &&
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
      r.grid.west === 138.516 &&
      r.geometry.circle[0] === "Polygon" && r.geometry.circle[1] > 40 && r.geometry.circle[2] === 1 &&
      JSON.stringify(r.geometry.clipped) === JSON.stringify(["LineString", [[0, 0.5], [1.5, 0.5]], "l"]) &&
      r.geometry.merged[0] === 1 && r.geometry.merged[1] >= 5 &&
      JSON.stringify(r.geometry.erased) === JSON.stringify(["a"]) &&
      JSON.stringify(r.geometry.overlaid) === JSON.stringify(["a/c", "b/c"]) &&
      /invalid buffer options/.test(r.geometry.badBuffer) &&
      // proj4js: (-5995.185, -35367.230) for Tokyo Station in EPSG:6677.
      JSON.stringify(r.geometry.ix) === JSON.stringify([-5995.185, -35367.23]) &&
      JSON.stringify(r.geometry.back) === JSON.stringify([139.7671, 35.6812]) &&
      JSON.stringify(r.geometry.inIx) === JSON.stringify([-5995.185, -35367.23]) &&
      r.geometry.planarRadius < 0.02 &&
      /unsupported CRS EPSG:9999/.test(r.geometry.unknownCrs) &&
      // proj4js: Paris in Lambert 93, Tokyo Station in plane IX on the Tokyo datum.
      JSON.stringify(r.geometry.paris) === JSON.stringify([652469.023, 6862035.259]) &&
      JSON.stringify(r.geometry.named) === JSON.stringify(r.geometry.paris) &&
      JSON.stringify(r.geometry.tokyoDatum) === JSON.stringify([-5701.993, -35723.01]) &&
      /unsupported projection: \+proj=geos/.test(r.geometry.badProj);
    return [ok, { loaded, ...r }];
  },

  // The examples that call the engine (bundle/main) directly: it starts and draws.
  async basic(page) {
    return engineStarted(page);
  },

  async terrain(page) {
    return engineStarted(page);
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

async function engineStarted(page) {
  const r = await page.evaluate(() => ({ frames: window.__mbmap.map_frame_count(window.__map) }));
  return [r.frames > 0, r];
}

// The camera API on the npm example's map (Tokyo Station, 800 x 600): event
// order, animations ending where asked, fitting a box, projecting, limits and
// handlers, and the keyboard and double click as MapLibre has them.
async function cameraChecks(page) {
  const r = await page.evaluate(async () => {
    const map = window.__map;
    const log = [];
    for (const t of ["movestart", "move", "moveend", "zoomstart", "zoom", "zoomend", "rotatestart", "rotateend", "pitchstart", "pitchend"]) {
      map.on(t, () => {
        if (!log.includes(t)) log.push(t);
      });
    }
    const ended = () => map.once("moveend");
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 14, bearing: 0, pitch: 0 });
    log.length = 0;
    const easeEnd = ended();
    map.easeTo({ center: [139.78, 35.69], zoom: 15, bearing: 30, pitch: 20, duration: 300 });
    const moving = map.isMoving() && map.isEasing();
    await easeEnd;
    const eased = { ...map.getCenter(), zoom: map.getZoom(), bearing: map.getBearing(), pitch: map.getPitch() };
    const events = log.slice();
    const flyEnd = ended();
    map.flyTo({ center: [139.7, 35.65], zoom: 13, duration: 400 });
    await flyEnd;
    const flown = { ...map.getCenter(), zoom: map.getZoom() };
    const box = [[139.75, 35.66], [139.8, 35.7]];
    const want = map.cameraForBounds(box, { padding: 40 });
    const fitEnd = ended();
    map.fitBounds(box, { padding: 40, duration: 200 });
    await fitEnd;
    const fit = { ...map.getCenter(), zoom: map.getZoom(), want };
    const p = map.project([139.77, 35.68]);
    const back = map.unproject(p);
    const bounds = map.getBounds();
    const inBounds = bounds.getWest() < 139.77 && bounds.getEast() > 139.77 && bounds.getSouth() < 35.68 && bounds.getNorth() > 35.68;
    map.setMaxBounds([139.7, 35.6, 139.8, 35.7]);
    // Flat, since the bounds hold the center's half view (pitch aside, as in MapLibre).
    map.jumpTo({ center: [150, 20], zoom: 14, pitch: 0 });
    const clamped = map.getBounds();
    window.__clamped = clamped.toArray();
    const kept = clamped.getWest() >= 139.7 - 1e-9 && clamped.getEast() <= 139.8 + 1e-9 && clamped.getSouth() >= 35.6 - 1e-9 && clamped.getNorth() <= 35.7 + 1e-9;
    map.setMaxBounds(null);
    map.setMaxZoom(16);
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 18 });
    const capped = map.getZoom();
    map.setMaxZoom(22);
    map.scrollZoom.disable();
    const handlers = { scroll: map.scrollZoom.isEnabled(), drag: map.dragPan.isEnabled() };
    let badLimit = "";
    try {
      map.setMinZoom(30);
    } catch (e) {
      badLimit = e.message;
    }
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 14, bearing: 0, pitch: 0 });
    return { moving, eased, events, flown, fit, p, back, inBounds, kept, capped, handlers, badLimit };
  });
  // Scroll zoom is off: the wheel does nothing.
  await page.mouse.move(400, 300);
  await page.mouse.wheel(0, 300);
  await page.waitForTimeout(300);
  const wheel = await page.evaluate(() => window.__map.getZoom());
  // ArrowRight pans 100 px east and `+` zooms in by 1, each over 300 ms.
  const before = await page.evaluate(() => window.__map.project([139.7671, 35.6812]).x);
  await page.click("canvas", { position: { x: 400, y: 300 } });
  await page.keyboard.press("ArrowRight");
  await page.evaluate(() => window.__map.once("moveend"));
  const keyed = await page.evaluate(() => window.__map.project([139.7671, 35.6812]).x);
  await page.keyboard.press("Equal");
  await page.evaluate(() => window.__map.once("moveend"));
  const plus = await page.evaluate(() => window.__map.getZoom());
  // A double click zooms in by 1 around the point clicked (in canvas pixels).
  const top = await page.evaluate(() => window.__map.getCanvas().getBoundingClientRect().top);
  const left = await page.evaluate(() => window.__map.getCanvas().getBoundingClientRect().left);
  const target = await page.evaluate(() => window.__map.unproject([600, 200]));
  await page.mouse.dblclick(left + 600, top + 200);
  await page.evaluate(() => window.__map.once("moveend"));
  const dbl = await page.evaluate((t) => ({ zoom: window.__map.getZoom(), at: window.__map.project(t) }), target);
  const ok =
    r.moving &&
    Math.abs(r.eased.lng - 139.78) < 1e-9 && Math.abs(r.eased.lat - 35.69) < 1e-9 &&
    r.eased.zoom === 15 && r.eased.bearing === 30 && r.eased.pitch === 20 &&
    // The order of first appearance, as MapLibre fires them.
    JSON.stringify(r.events) === JSON.stringify(["movestart", "zoomstart", "rotatestart", "pitchstart", "move", "zoom", "zoomend", "rotateend", "pitchend", "moveend"]) &&
    Math.abs(r.flown.lng - 139.7) < 1e-9 && r.flown.zoom === 13 &&
    Math.abs(r.fit.lng - r.fit.want.center.lng) < 1e-9 && Math.abs(r.fit.zoom - r.fit.want.zoom) < 1e-9 &&
    Math.abs(r.back.lng - 139.77) < 1e-9 && Math.abs(r.back.lat - 35.68) < 1e-9 &&
    r.inBounds && r.kept && r.capped === 16 &&
    r.handlers.scroll === false && r.handlers.drag === true &&
    /zoom limits/.test(r.badLimit) &&
    wheel === 14 &&
    Math.abs(keyed - (before - 100)) < 1e-6 &&
    plus === 15 &&
    Math.abs(dbl.zoom - 16) < 1e-9 && Math.abs(dbl.at.x - 600) < 1e-6 && Math.abs(dbl.at.y - 200) < 1e-6;
  const clamped = await page.evaluate(() => window.__clamped);
  return { ok, ...r, clamped, wheel, before, keyed, plus, dbl };
}

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
