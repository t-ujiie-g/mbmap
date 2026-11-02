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

// Where each check's page is.
const PAGES = {
  npm: "bench/npm/pages/npm/",
  element: "bench/npm/pages/element/",
  geojson: "bench/npm/pages/geojson/",
  analysis: "bench/npm/pages/analysis/",
  basic: "bench/pages/basic/",
  terrain: "bench/pages/terrain/",
  "showcase-html": "examples/html/?local=1",
  "showcase-element": "examples/element/?local=1",
  "showcase-react": "examples/react/?local=1",
};

// Each check runs in a fresh page and returns [name, ok, details].
const checks = {
  async npm(page, requests) {
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
      const missing = new Map({ container: div, style: "/bench/npm/pages/npm/missing.json" });
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
    const query = await queryChecks(page);
    const style = await styleChecks(page, requests);
    const camera = await cameraChecks(page);
    return [ok && query.ok && style.ok && camera.ok, { ...r, query, style, camera }];
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

  async "showcase-html"(page) {
    return showcase(page);
  },

  async "showcase-element"(page) {
    return showcase(page);
  },

  async "showcase-react"(page) {
    return showcase(page);
  },
};

// The showcase, the same in all three examples: at Tokyo Station the panel
// lists it within 5 km and gives plane IX's coordinates (proj4js: X -35367.230,
// Y -5995.185); 3D tilts to 60° on terrain; a destination button flies there,
// and the panel follows the camera.
async function showcase(page) {
  await page.waitForFunction(() => window.__described);
  const first = await page.evaluate(() => window.__described);
  const panel = () => page.evaluate(() => document.getElementById("camera").textContent);
  // A click at Tokyo Station, at the center, shows the place on top.
  await page.mouse.click(400, 300);
  await page.waitForFunction(() => window.__picked);
  const picked = await page.evaluate(() => ({ rows: window.__picked, text: document.getElementById("picked").textContent }));
  await page.click("#modes button >> text=3D");
  await page.waitForFunction(() => window.__map && window.__map.getPitch() === 60 && !window.__map.isMoving(), null, { timeout: 30000 });
  const tilted = await page.evaluate(() => ({ pitch: window.__map.getPitch(), bearing: window.__map.getBearing() }));
  await page.click("#destinations button >> text=大阪駅");
  await page.waitForFunction(() => Math.abs(window.__map.getCenter().lng - 135.4959) < 1e-9 && !window.__map.isMoving(), null, { timeout: 30000 });
  await page.waitForFunction(() => window.__described.near.includes("大阪駅"));
  const osaka = await page.evaluate(() => window.__described);
  const shown = await panel();
  // The 3D switch went through setStyle; layer groups hide through setLayoutProperty and markers go in with setData.
  const styled = await page.evaluate(async () => {
    const map = window.__map;
    const idle = () => map.once("idle");
    let wait = idle();
    document.querySelector("#layers button").click();
    await wait;
    const hillshade = map.getLayoutProperty("hillshade", "visibility");
    wait = idle();
    document.getElementById("marker").click();
    await wait;
    return { same: map === window.__map, terrain: map.getTerrain(), hillshade, markers: map.getStyle().sources.places.data.features.at(-1).properties.name };
  });
  const ok =
    ["places", "places-label"].includes(picked.rows[0][1]) && picked.text.includes("東京駅") &&
    styled.terrain?.source === "dem" && styled.hillshade === "none" && styled.markers === "印 1" &&
    first.near.includes("東京駅") && !first.near.includes("新宿駅") &&
    first.plane.zone === "第IX系" &&
    Math.abs(first.plane.x - -5995.185) < 0.01 && Math.abs(first.plane.y - -35367.23) < 0.01 &&
    tilted.pitch === 60 && tilted.bearing === -20 &&
    osaka.plane.zone === "第VI系" &&
    shown.includes("135.49590") && shown.includes("第VI系");
  return [ok, { first, picked, tilted, osaka: osaka.near, shown, styled }];
}

// Queries and mouse events on the npm example's map (Tokyo Station, 800 x 600):
// what is under a point, a layer's click and hover events, a source's features,
// and the error paths (bench/query/golden.mjs compares the results with MapLibre).
async function queryChecks(page) {
  const found = await page.evaluate(async () => {
    const map = window.__map;
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 });
    await map.once("idle");
    // A screen point with a building on top, and one with nothing of the layer.
    let building = null;
    for (let y = 100; y < 500 && !building; y += 20)
      for (let x = 100; x < 700 && !building; x += 20) {
        const fs = await map.queryRenderedFeatures([x, y], { layers: ["building"] });
        if (fs.length > 0) building = [x, y];
      }
    const center = (await map.queryRenderedFeatures([400, 300])).map((x) => x.layer.id);
    const at = building ? await map.queryRenderedFeatures(building) : [];
    const errors = [];
    const f = (e) => errors.push(e.error.message);
    map.on("error", f);
    const unknown = await map.queryRenderedFeatures({ layers: ["nope"] });
    map.off("error", f);
    let refused = "";
    await map.queryRenderedFeatures({ filter: ["sqrt", 2] }).catch((e) => (refused = e.message));
    const roads = await map.querySourceFeatures("gsi", { sourceLayer: "road" });
    const box = await map.queryRenderedFeatures([[0, 0], [800, 600]], { layers: ["road"], filter: ["==", ["get", "rdCtg"], 0] });
    window.__events = [];
    map.on("click", (e) => window.__events.push(["click", Math.round(e.point.x), Math.round(e.point.y), e.lngLat.lng > 139]));
    map.on("click", "building", (e) => window.__events.push(["click-building", e.features[0].layer.id, e.features[0].sourceLayer]));
    map.on("mouseenter", "building", () => window.__events.push(["enter"]));
    map.on("mouseleave", "building", () => window.__events.push(["leave"]));
    const r = map.getCanvas().getBoundingClientRect();
    return {
      building, center, wlog: { ...globalThis.__wlog, errors: [...(globalThis.__wlog.errors ?? [])] }, origin: [r.left, r.top], top: at[0]?.layer.id, source: at[0]?.source, state: at[0]?.state,
      geometry: at.find((x) => x.layer.id === "building")?.geometry.type, errors, unknown: unknown.length, refused,
      roads: roads.length, roadTypes: [...new Set(roads.map((x) => x.geometry.type))], box: box.length,
      boxAll: box.every((x) => x.layer.id === "road" && x.properties.rdCtg === 0),
    };
  });
  if (!found.building) return { ok: false, ...found };
  const [x, y] = [found.origin[0] + found.building[0], found.origin[1] + found.building[1]];
  await page.mouse.move(found.origin[0] + 5, found.origin[1] + 5);
  await page.mouse.move(x, y, { steps: 4 });
  await page.waitForTimeout(300);
  await page.mouse.click(x, y);
  // A drag is not a click.
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x + 30, y, { steps: 3 });
  await page.mouse.up();
  await page.mouse.move(x + 400, y + 400, { steps: 2 });
  await page.waitForTimeout(300);
  const events = await page.evaluate(() => window.__events);
  const clicks = events.filter((e) => e[0] === "click");
  const ok =
    found.building !== null &&
    found.source === "gsi" && JSON.stringify(found.state) === "{}" &&
    ["Polygon", "LineString", "MultiPolygon"].includes(found.geometry) &&
    found.unknown === 0 && /'nope' does not exist/.test(found.errors[0] ?? "") &&
    /unsupported: expression sqrt/.test(found.refused) &&
    found.roads > 1000 && found.roadTypes.every((t) => t === "LineString" || t === "MultiLineString") &&
    found.box > 0 && found.boxAll &&
    clicks.length === 1 && clicks[0][1] === found.building[0] && clicks[0][2] === found.building[1] && clicks[0][3] &&
    events.some((e) => e[0] === "click-building" && e[1] === "building" && e[2] === "building") &&
    events.filter((e) => e[0] === "enter").length >= 1 &&
    events.at(-1)[0] === "leave";
  return { ok, ...found, events };
}

// The colour of screen pixel (x, y), read from a screenshot.
async function pixel(page, x, y) {
  const png = await page.screenshot({ clip: { x, y, width: 1, height: 1 } });
  return page.evaluate(async (b64) => {
    const bitmap = await createImageBitmap(await (await fetch(`data:image/png;base64,${b64}`)).blob());
    const ctx = new OffscreenCanvas(1, 1).getContext("2d");
    ctx.drawImage(bitmap, 0, 0);
    return [...ctx.getImageData(0, 0, 1, 1).data.slice(0, 3)];
  }, png.toString("base64"));
}

const near = (rgb, want) => rgb.every((v, i) => Math.abs(v - want[i]) <= 3);

// The style API on the npm example's map: paint changes, hiding, moving and
// removing layers keep the tiles, showing a layer again loads them, setStyle swaps everything,
// GeoJSON sources come and go, and refused changes fire `error` and keep the style.
async function styleChecks(page, requests) {
  const tiles = () => requests.filter((u) => u.endsWith(".pbf")).length;
  const step = (f) =>
    page.evaluate(async (body) => {
      const map = window.__map;
      const idle = map.once("idle");
      const out = new Function("map", body)(map);
      await idle;
      return out;
    }, f);
  await step("map.jumpTo({ center: [139.7671, 35.6812], zoom: 14.5, bearing: 0, pitch: 0 });");
  const before = tiles();
  const original = await step('const s = map.getStyle(); map.setPaintProperty("waterarea", "fill-color", "#00ff00"); map.setPaintProperty("background", "background-color", "#ff0000"); return s;');
  const painted = tiles();
  await step('map.setLayoutProperty("waterarea", "visibility", "none"); map.moveLayer("road", "waterarea"); map.removeLayer("railway");');
  const kept = tiles();
  await step('map.setLayoutProperty("waterarea", "visibility", "visible");');
  const relaid = tiles();
  const errors = await page.evaluate(() => {
    const map = window.__map;
    const out = [];
    const f = (e) => out.push(e.error.message);
    map.on("error", f);
    map.setPaintProperty("nope", "fill-color", "#000");
    map.removeSource("gsi");
    map.setPaintProperty("road", "line-width", ["sqrt", 2]);
    map.off("error", f);
    return { out, width: map.getPaintProperty("road", "line-width"), order: map.getLayersOrder().slice(0, 4) };
  });
  await step('map.setStyle({ version: 8, sources: {}, layers: [{ id: "bg", type: "background", paint: { "background-color": "#ff0000" } }] });');
  const red = await pixel(page, 400, 300);
  const swapped = tiles();
  const point = (lng, lat) => ({ type: "FeatureCollection", features: [{ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [lng, lat] } }] });
  await step(`map.addSource("pts", { type: "geojson", data: ${JSON.stringify(point(139.7671, 35.6812))} }); map.addLayer({ id: "pts", type: "circle", source: "pts", paint: { "circle-radius": 30, "circle-color": "#0000ff" } });`);
  const blue = await pixel(page, 400, 300);
  await step(`map.getSource("pts").setData(${JSON.stringify(point(139.8, 35.7))});`);
  const moved = await pixel(page, 400, 300);
  const order = await step('map.removeLayer("pts"); map.removeSource("pts"); return [map.getLayersOrder(), Object.keys(map.getStyle().sources)];');
  await step(`map.setStyle(${JSON.stringify(original)});`);
  const restored = { tiles: tiles(), center: await pixel(page, 400, 300), layers: await page.evaluate(() => window.__map.getLayersOrder().length) };
  const ok =
    painted === before &&
    kept === painted &&
    relaid > kept &&
    errors.out.length === 3 &&
    /no layer "nope"/.test(errors.out[0]) &&
    /used by layer "road"/.test(errors.out[1]) &&
    /unsupported: expression sqrt/.test(errors.out[2]) &&
    errors.width?.[0] === "interpolate" &&
    JSON.stringify(errors.order) === JSON.stringify(["background", "road", "waterarea", "structurea"]) &&
    near(red, [255, 0, 0]) &&
    swapped === relaid &&
    near(blue, [0, 0, 255]) &&
    near(moved, [255, 0, 0]) &&
    JSON.stringify(order) === JSON.stringify([["bg"], []]) &&
    restored.tiles > swapped &&
    !near(restored.center, [255, 0, 0]) &&
    restored.layers === original.layers.length;
  return { ok, before, painted, kept, relaid, errors, red, swapped, blue, moved, order, restored };
}

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
    // Diagnostics: query messages sent to workers and their answers.
    await page.addInitScript(() => {
      const W = globalThis.Worker;
      globalThis.__wlog = { sent: 0, answered: 0, hits: 0, tiles: 0, drops: 0 };
      globalThis.Worker = class extends W {
        constructor(...a) {
          super(...a);
          this.addEventListener("message", (e) => {
            if (e.data?.type === "query") { __wlog.answered++; __wlog.hits += e.data.hits?.length ?? 0; }
            if (e.data?.type === "tile") __wlog.tiles++;
            if (e.data?.type === "error") (__wlog.errors ??= new Set()).add(String(e.data.message).slice(0, 200));
          });
        }
        postMessage(m, t) {
          if (m?.type === "query") __wlog.sent++;
          if (m?.type === "drop") __wlog.drops++;
          return super.postMessage(m, t);
        }
      };
    });
    // 404s are expected (missing style, missing fixtures); so are the
    // rejections the element and style checks provoke.
    const expected = /404|mb-map: invalid|no layer "nope"|"gsi" is used by layer|expression sqrt|'nope' does not exist/;
    page.on("console", (m) => m.type() === "error" && !expected.test(m.text()) && errors.push(m.text()));
    await page.goto(`${origin}/${PAGES[example]}`);
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
