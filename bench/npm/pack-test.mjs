// Checks the examples built on the packed package in Chromium; without the
// fixtures tiles 404 and maps load empty, so CI runs it too.
// Usage: node npm/pack-test.mjs [--screenshots=dir]
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";
import { encodePng } from "../lib/png.mjs";
import { writeArchive } from "../lib/pmtiles-writer.mjs";
import { ROOT } from "../lib/root.mjs";
import { serve } from "../lib/serve.mjs";
import { prepareExamples } from "./prepare.mjs";
import { fakeGeolocation } from "../lib/fake-geolocation.mjs";

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
    const state = await stateChecks(page);
    const tiles = await tileSourceChecks(page);
    const exported = await trackExportChecks(page);
    const style = await styleChecks(page, requests);
    const camera = await cameraChecks(page);
    return [ok && query.ok && state.ok && tiles.ok && exported.ok && style.ok && camera.ok, { ...r, query, state, tiles, exported, style, camera }];
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

// The showcase, alike in all three examples: Tokyo Station within 5 km and in plane IX (proj4js:
// X -35367.230, Y -5995.185), 3D on terrain, a flight to a destination, the panel following the
// camera, the destinations' pins on their places, and the view saved as a PNG.
async function showcase(page) {
  await page.waitForFunction(() => window.__described);
  const first = await page.evaluate(() => window.__described);
  const pin = (name) => page.evaluate((n) => [...window.__pins.children].find((p) => p.textContent === n)?.style.transform, name);
  const tokyoPin = await pin("東京駅");
  const panel = () => page.evaluate(() => document.getElementById("camera").textContent);
  // A click at Tokyo Station, at the center, shows the place on top.
  await page.mouse.click(400, 300);
  await page.waitForFunction(() => window.__picked);
  const picked = await page.evaluate(() => ({ rows: window.__picked, text: document.getElementById("picked").textContent }));
  // The identify controller selects the top feature and highlights it through feature state; the
  // coordinates follow the pointer in four systems (two through mbmap/analysis).
  const identified = await page.evaluate(() => {
    const s = window.__identify.state;
    const top = s.features[0];
    return { count: s.features.length, index: s.index, top: top.layer.id, selected: window.__map.getFeatureState({ source: top.source, id: top.id }).selected };
  });
  await page.mouse.move(420, 320);
  await page.waitForFunction(() => window.__coordinates.state.source === "pointer" && window.__coordinates.state.values.every((v) => v.text));
  const coordinates = await page.evaluate(() => window.__coordinates.state.values.map((v) => [v.id, v.text]));
  // Hovering the place sets its feature state.
  await page.mouse.move(420, 320);
  await page.mouse.move(400, 300, { steps: 3 });
  await page.waitForFunction(() => window.__hovered);
  const hovered = await page.evaluate(() => ({ id: window.__hovered, state: window.__map.getFeatureState({ source: "places", id: window.__hovered }) }));
  const measured = await measureChecks(page);
  await page.click("#modes button >> text=3D");
  await page.waitForFunction(() => window.__map && window.__map.getPitch() === 60 && !window.__map.isMoving(), null, { timeout: 30000 });
  const tilted = await page.evaluate(() => ({ pitch: window.__map.getPitch(), bearing: window.__map.getBearing() }));
  await page.click("#destinations button >> text=大阪駅");
  await page.waitForFunction(() => Math.abs(window.__map.getCenter().lng - 135.4959) < 1e-9 && !window.__map.isMoving(), null, { timeout: 30000 });
  await page.waitForFunction(() => window.__described.near.includes("大阪駅"));
  const osaka = await page.evaluate(() => window.__described);
  const shown = await panel();
  const osakaPin = await pin("大阪駅");
  await page.click("#save");
  await page.waitForFunction(() => window.__saved, null, { timeout: 30000 });
  const saved = await page.evaluate(() => window.__saved);
  const controls = await controlChecks(page);
  const searched = await searchChecks(page);
  // The 3D switch went through setStyle; layer groups hide through setLayoutProperty and markers go in with setData.
  const styled = await page.evaluate(async () => {
    const map = window.__map;
    const idle = () => map.once("idle");
    let wait = idle();
    const panel = window.__panel;
    panel.layers.toggle("陰影");
    await wait;
    const hillshade = map.getLayoutProperty("hillshade", "visibility");
    const hillshadeItem = panel.layers.state.items.find((i) => i.id === "陰影");
    // Hidden but within its zoom range: still `inRange`.
    const listed = { visible: hillshadeItem.visible, inRange: hillshadeItem.inRange };
    wait = idle();
    document.getElementById("marker").click();
    await wait;
    const legend = panel.legend.state.entries.find((e) => e.id === "road");
    // The photo basemap keeps the places (an overlay) with the marker just added.
    wait = idle();
    panel.basemaps.select("photo");
    await wait;
    const photo = { layers: map.getStyle().layers.map((l) => l.id), marker: map.getStyle().sources.places.data.features.at(-1).properties.name };
    wait = idle();
    panel.basemaps.select("map");
    await wait;
    return {
      same: map === window.__map, terrain: map.getTerrain(), hillshade, listed, markers: map.getStyle().sources.places.data.features.at(-1).properties.name,
      legend: legend && { title: legend.title, kind: legend.kind, labels: legend.items.map((i) => i.label) }, photo, back: map.getLayer("road") !== undefined,
    };
  });
  const ok =
    ["places", "places-label"].includes(picked.rows[0][1]) && picked.text.includes("東京駅") &&
    identified.count >= 1 && identified.index === 0 && identified.selected === true &&
    coordinates.length === 4 && /^35\.68\d+, 139\.76\d+$/.test(coordinates[0][1]) && /N 139°46′/.test(coordinates[1][1]) &&
    coordinates[2][1].startsWith("第IX系 X -35") && coordinates[3][1].startsWith("54N ") &&
    hovered.id === "東京駅" && hovered.state.hover === true &&
    styled.terrain?.source === "dem" && styled.hillshade === "none" && styled.listed.visible === false && styled.listed.inRange === true && styled.markers === "印 1" &&
    JSON.stringify(styled.legend) === JSON.stringify({ title: "道路", kind: "match", labels: ["0", "1", "その他"] }) &&
    styled.photo.layers.includes("photo") && !styled.photo.layers.includes("road") && styled.photo.layers.at(-1) === "places-label" && styled.photo.marker === "印 1" && styled.back &&
    first.near.includes("東京駅") && !first.near.includes("新宿駅") &&
    first.plane.zone === "第IX系" &&
    Math.abs(first.plane.x - -5995.185) < 0.01 && Math.abs(first.plane.y - -35367.23) < 0.01 &&
    tilted.pitch === 60 && tilted.bearing === -20 &&
    osaka.plane.zone === "第VI系" &&
    shown.includes("135.49590") && shown.includes("第VI系") &&
    atCentre(tokyoPin) && atCentre(osakaPin) &&
    saved.type === "image/png" && saved.size > 0 && controls.ok && searched.ok && measured.ok;
  return [ok, { first, picked, identified, coordinates, hovered, tilted, osaka: osaka.near, shown, styled, tokyoPin, osakaPin, saved, controls, searched, measured }];
}

// Queries and mouse events on a GeoJSON source added to the npm example's map (CI has no tile
// fixtures): points, layers, filters, source features, layer events and error paths.
async function queryChecks(page) {
  const found = await page.evaluate(async () => {
    const map = window.__map;
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 });
    await map.once("idle");
    // A square west of the center, a line across it and a point on it.
    const [w, s] = [map.unproject([200, 400]), map.unproject([300, 200])];
    const square = [[w.lng, w.lat], [s.lng, w.lat], [s.lng, s.lat], [w.lng, s.lat], [w.lng, w.lat]];
    const mid = map.unproject([250, 300]);
    const data = {
      type: "FeatureCollection",
      features: [
        { type: "Feature", properties: { kind: "area", n: 1 }, geometry: { type: "Polygon", coordinates: [square] } },
        { type: "Feature", properties: { kind: "road", n: 2 }, geometry: { type: "LineString", coordinates: [[w.lng, mid.lat], [s.lng, mid.lat]] } },
        { type: "Feature", properties: { kind: "spot", n: 3 }, geometry: { type: "Point", coordinates: [mid.lng, mid.lat] } },
      ],
    };
    const idle = map.once("idle");
    map.addSource("q", { type: "geojson", data });
    map.addLayer({ id: "q-area", type: "fill", source: "q", filter: ["==", ["get", "kind"], "area"] });
    map.addLayer({ id: "q-road", type: "line", source: "q", filter: ["==", ["get", "kind"], "road"], paint: { "line-width": 6 } });
    map.addLayer({ id: "q-spot", type: "circle", source: "q", filter: ["==", ["get", "kind"], "spot"], paint: { "circle-radius": 8 } });
    await idle;
    const ids = (fs) => fs.map((f) => f.layer.id);
    const atSpot = await map.queryRenderedFeatures([250, 300], { layers: ["q-area", "q-road", "q-spot"] });
    const inArea = await map.queryRenderedFeatures([220, 380], { layers: ["q-area", "q-road", "q-spot"] });
    const outside = await map.queryRenderedFeatures([600, 300], { layers: ["q-area", "q-road", "q-spot"] });
    const box = await map.queryRenderedFeatures([[190, 190], [310, 410]], { filter: [">=", ["get", "n"], 2] });
    const errors = [];
    const f = (e) => errors.push(e.error.message);
    map.on("error", f);
    const unknown = await map.queryRenderedFeatures({ layers: ["nope"] });
    map.off("error", f);
    let refused = "";
    await map.queryRenderedFeatures({ filter: ["sqrt", 2] }).catch((e) => (refused = e.message));
    const source = await map.querySourceFeatures("q");
    window.__events = [];
    map.on("click", (e) => window.__events.push(["click", Math.round(e.point.x), Math.round(e.point.y), e.lngLat.lng > 139]));
    map.on("click", "q-area", (e) => window.__events.push(["click-area", e.features[0].layer.id, e.features[0].properties.n]));
    map.on("mouseenter", "q-area", () => window.__events.push(["enter"]));
    map.on("mouseleave", "q-area", () => window.__events.push(["leave"]));
    const r = map.getCanvas().getBoundingClientRect();
    return {
      origin: [r.left, r.top],
      atSpot: ids(atSpot), spot: atSpot[0] && { source: atSpot[0].source, state: atSpot[0].state, geometry: atSpot[0].geometry.type, n: atSpot[0].properties.n },
      inArea: ids(inArea), outside: outside.length, box: ids(box).filter((id) => id.startsWith("q-")),
      errors, unknown: unknown.length, refused,
      source: source.map((x) => x.properties.n).sort(),
    };
  });
  const [x, y] = [found.origin[0] + 220, found.origin[1] + 380];
  await page.mouse.move(found.origin[0] + 600, found.origin[1] + 500);
  await page.mouse.move(x, y, { steps: 4 });
  await page.waitForTimeout(300);
  await page.mouse.click(x, y);
  // A drag is not a click.
  await page.mouse.down();
  await page.mouse.move(x + 30, y, { steps: 3 });
  await page.mouse.up();
  await page.mouse.move(found.origin[0] + 600, found.origin[1] + 500, { steps: 2 });
  await page.waitForTimeout(300);
  const events = await page.evaluate(async () => {
    const map = window.__map;
    for (const id of ["q-spot", "q-road", "q-area"]) map.removeLayer(id);
    map.removeSource("q");
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 15 });
    return window.__events;
  });
  const clicks = events.filter((e) => e[0] === "click");
  const ok =
    JSON.stringify(found.atSpot) === JSON.stringify(["q-spot", "q-road", "q-area"]) &&
    found.spot?.source === "q" && JSON.stringify(found.spot.state) === "{}" && found.spot.geometry === "Point" && found.spot.n === 3 &&
    JSON.stringify(found.inArea) === JSON.stringify(["q-area"]) &&
    found.outside === 0 &&
    JSON.stringify(found.box) === JSON.stringify(["q-spot", "q-road"]) &&
    found.unknown === 0 && /'nope' does not exist/.test(found.errors[0] ?? "") &&
    /unsupported: expression sqrt/.test(found.refused) &&
    // The square spans two tiles, and each gives its part, as MapLibre's do.
    JSON.stringify([...new Set(found.source)]) === JSON.stringify([1, 2, 3]) &&
    clicks.length === 1 && clicks[0][1] === 220 && clicks[0][2] === 380 && clicks[0][3] &&
    events.some((e) => e[0] === "click-area" && e[1] === "q-area" && e[2] === 1) &&
    events.filter((e) => e[0] === "enter").length >= 1 &&
    events.at(-1)[0] === "leave";
  return { ok, ...found, events };
}

// Feature state on the npm example's map: two squares, one by GeoJSON id and
// one by a promoted property, are drawn red while their state says `on`.
async function stateChecks(page) {
  const step = (body) =>
    page.evaluate(async (b) => {
      const map = window.__map;
      const idle = map.once("idle");
      const out = new Function("map", b)(map);
      await idle;
      return out;
    }, body);
  await step(`
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 });
    const square = (x0, y0, x1, y1) => {
      const [a, b] = [map.unproject([x0, y1]), map.unproject([x1, y0])];
      return { type: "Polygon", coordinates: [[[a.lng, a.lat], [b.lng, a.lat], [b.lng, b.lat], [a.lng, b.lat], [a.lng, a.lat]]] };
    };
    const color = ["case", ["boolean", ["feature-state", "on"], false], "#ff0000", "#0000ff"];
    map.addSource("st", { type: "geojson", data: { type: "FeatureCollection", features: [
      { type: "Feature", id: 1, properties: {}, geometry: square(100, 100, 200, 200) },
    ] } });
    map.addSource("pr", { type: "geojson", promoteId: "key", data: { type: "FeatureCollection", features: [
      { type: "Feature", properties: { key: "b" }, geometry: square(300, 100, 400, 200) },
    ] } });
    map.addLayer({ id: "st", type: "fill", source: "st", paint: { "fill-color": color } });
    map.addLayer({ id: "pr", type: "fill", source: "pr", paint: { "fill-color": color } });`);
  const colors = async () => [await pixel(page, 150, 150), await pixel(page, 350, 150)];
  const before = await colors();
  const set = await step(`
    map.setFeatureState({ source: "st", id: 1 }, { on: true });
    map.setFeatureState({ source: "pr", id: "b" }, { on: true, other: 2 });`);
  const on = await colors();
  const read = await page.evaluate(async () => {
    const map = window.__map;
    const errors = [];
    const f = (e) => errors.push(e.error.message);
    map.on("error", f);
    map.setFeatureState({ source: "gsi", id: 1 }, { on: true });
    map.setFeatureState({ source: "nope", id: 1 }, { on: true });
    map.off("error", f);
    const [hit] = await map.queryRenderedFeatures([350, 150], { layers: ["pr"] });
    return { state: map.getFeatureState({ source: "pr", id: "b" }), queried: hit?.state, id: hit?.id, errors };
  });
  await step(`map.removeFeatureState({ source: "pr", id: "b" }, "on"); map.removeFeatureState({ source: "st" });`);
  const off = await colors();
  const left = await page.evaluate(() => {
    const map = window.__map;
    const out = { st: map.getFeatureState({ source: "st", id: 1 }), pr: map.getFeatureState({ source: "pr", id: "b" }) };
    for (const id of ["st", "pr"]) {
      map.removeLayer(id);
      map.removeSource(id);
    }
    return out;
  });
  const red = (c) => near(c, [255, 0, 0]);
  const blue = (c) => near(c, [0, 0, 255]);
  const ok =
    blue(before[0]) && blue(before[1]) &&
    red(on[0]) && red(on[1]) &&
    JSON.stringify(read.state) === JSON.stringify({ on: true, other: 2 }) &&
    JSON.stringify(read.queried) === JSON.stringify({ on: true, other: 2 }) && read.id === "b" &&
    /sourceLayer parameter must be provided/.test(read.errors[0] ?? "") && /'nope' does not exist/.test(read.errors[1] ?? "") &&
    blue(off[0]) && blue(off[1]) &&
    JSON.stringify(left) === JSON.stringify({ st: {}, pr: { other: 2 } });
  return { ok, before, on, read, off, left, set };
}

// Raster sources on the npm example's map, from files written here (CI has no
// tile fixtures): a tile template, a TileJSON document and a PMTiles archive,
// each a solid color; raster paint; and a transformRequest that rewrites tiles.
async function tileSourceChecks(page) {
  const dir = path.join(ROOT, "bench/dist/pack");
  await mkdir(dir, { recursive: true });
  const solid = (r, g, b) => {
    const rgba = new Uint8Array(256 * 256 * 4);
    for (let i = 0; i < rgba.length; i += 4) rgba.set([r, g, b, 255], i);
    return encodePng(256, 256, rgba);
  };
  await writeFile(path.join(dir, "red.png"), solid(255, 0, 0));
  await writeFile(path.join(dir, "green.png"), solid(0, 255, 0));
  await writeFile(path.join(dir, "tiles.json"), JSON.stringify({ tilejson: "3.0.0", tiles: ["green.png"], attribution: "TileJSON test" }));
  await writeFile(path.join(dir, "blue.pmtiles"), writeArchive([{ z: 0, x: 0, y: 0, bytes: solid(0, 0, 255) }], { tileType: 2 }));
  const step = (body) =>
    page.evaluate(async (b) => {
      const map = window.__map;
      const idle = map.once("idle");
      const out = await new Function("map", `return (async () => { ${b} })()`)(map);
      await idle;
      return out;
    }, body);
  const centre = () => pixel(page, 400, 300);
  await step(`map.jumpTo({ center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 });
    map.addSource("t", { type: "raster", tiles: ["/bench/dist/pack/red.png"], tileSize: 256 });
    map.addLayer({ id: "t", type: "raster", source: "t" });`);
  const red = await centre();
  await step(`map.setPaintProperty("t", "raster-opacity", 0.5);`);
  const half = await centre();
  await step(`map.removeLayer("t"); map.removeSource("t");
    map.addSource("j", { type: "raster", url: "/bench/dist/pack/tiles.json", tileSize: 256 });
    map.addLayer({ id: "j", type: "raster", source: "j" });`);
  const green = await centre();
  const attribution = await page.evaluate(() => document.querySelector("#map > div")?.textContent);
  await step(`map.removeLayer("j"); map.removeSource("j");
    map.addSource("p", { type: "raster", url: "pmtiles:///bench/dist/pack/blue.pmtiles", tileSize: 256 });
    map.addLayer({ id: "p", type: "raster", source: "p" });`);
  const blue = await centre();
  await step(`map.removeLayer("p"); map.removeSource("p");
    window.__asked = [];
    map.setTransformRequest((url, type) => { window.__asked.push(type); return { url: url.replace("red.png", "green.png") }; });
    map.addSource("x", { type: "raster", tiles: ["/bench/dist/pack/red.png"], tileSize: 256 });
    map.addLayer({ id: "x", type: "raster", source: "x" });`);
  const transformed = await centre();
  const types = await page.evaluate(() => {
    const map = window.__map;
    map.removeLayer("x");
    map.removeSource("x");
    map.setTransformRequest(null);
    return [...new Set(window.__asked)];
  });
  const ok =
    // Half red over the light background.
    near(red, [255, 0, 0]) && half[0] > 200 && half[1] > 90 && half[1] < 170 &&
    near(green, [0, 255, 0]) && /TileJSON test/.test(attribution ?? "") &&
    near(blue, [0, 0, 255]) &&
    near(transformed, [0, 255, 0]) && JSON.stringify(types) === JSON.stringify(["Tile"]);
  return { ok, red, half, green, attribution, blue, transformed, types };
}

// Tracking and export over a red raster tile (tileSourceChecks' red.png): a tracked place follows
// each frame and stops once removed; parts at 2x equal the whole image; bad sizes are refused.
async function trackExportChecks(page) {
  const r = await page.evaluate(async () => {
    const map = window.__map;
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 });
    let idle = map.once("idle");
    map.addSource("e", { type: "raster", tiles: ["/bench/dist/pack/red.png"], tileSize: 256 });
    map.addLayer({ id: "e", type: "raster", source: "e" });
    await idle;
    const seen = [];
    const t = map.track([139.7671, 35.6812], (p) => seen.push(p));
    const atOnce = seen.length;
    let renders = 0;
    const counted = () => renders++;
    map.on("render", counted);
    idle = map.once("idle");
    map.panBy([100, 50], { duration: 0 });
    await idle;
    map.off("render", counted);
    const moved = seen.at(-1);
    t.setLngLat([139.7, 35.6]);
    const set = { at: t.getLngLat(), last: seen.at(-1) };
    t.remove();
    const before = seen.length;
    idle = map.once("idle");
    map.jumpTo({ center: [139.7671, 35.6812] });
    await idle;
    const pixels = async (blob) => {
      const bitmap = await createImageBitmap(blob);
      const ctx = new OffscreenCanvas(bitmap.width, bitmap.height).getContext("2d");
      ctx.drawImage(bitmap, 0, 0);
      return { width: bitmap.width, height: bitmap.height, data: ctx.getImageData(0, 0, bitmap.width, bitmap.height).data };
    };
    const whole = await pixels(await map.toBlob({ pixelRatio: 2 }));
    const parts = await pixels(await map.toBlob({ pixelRatio: 2, maxSize: 300 }));
    const same = whole.data.every((v, i) => v === parts.data[i]);
    const centre = [...whole.data.slice((600 * 1600 + 800) * 4, (600 * 1600 + 800) * 4 + 3)];
    const refused = [];
    for (const o of [{ pixelRatio: 0 }, { pixelRatio: 100 }]) await map.toBlob(o).catch((e) => refused.push(e.message));
    map.removeLayer("e");
    map.removeSource("e");
    return { first: seen[0], atOnce, moved, renders, set, after: seen.length - before, size: [whole.width, whole.height], same, centre, refused };
  });
  const ok =
    r.atOnce === 1 && Math.abs(r.first.x - 400) < 1e-6 && Math.abs(r.first.y - 300) < 1e-6 && r.first.covered === false &&
    Math.abs(r.moved.x - 300) < 1e-6 && Math.abs(r.moved.y - 250) < 1e-6 && r.renders > 0 &&
    r.set.at.lng === 139.7 && r.set.last.x < 0 &&
    r.after === 0 &&
    JSON.stringify(r.size) === "[1600,1200]" && r.same && near(r.centre, [255, 0, 0]) &&
    r.refused[0] === "mbmap: pixelRatio must be a positive number: 0" && r.refused[1] === "mbmap: cannot make a 80000 x 60000 image";
  return { ok, ...r };
}

// The showcase's map controls from `mbmap/ui` (drawn differently by each
// example): a scale and the attributions, zoom through the navigation, and the
// location from the fake Geolocation followed by the camera, its dot drawn.
async function controlChecks(page) {
  const r = await page.evaluate(async () => {
    const c = window.__controls;
    const map = window.__map;
    const moved = () => map.once("moveend");
    const zoom = map.getZoom();
    let end = moved();
    c.nav.zoomIn();
    await end;
    const zoomedIn = map.getZoom();
    end = moved();
    c.nav.zoomOut();
    await end;
    c.geo.trigger();
    end = moved();
    window.__geo.push(139.7, 35.66, 80);
    await end;
    const center = map.getCenter();
    const located = await new Promise((resolve) => setTimeout(() => resolve(document.querySelector(".location:not([hidden]), .react-location") !== null), 100));
    return {
      scale: c.scale.state.label,
      credits: c.attribution.state.text,
      zoom,
      zoomedIn,
      status: c.geo.state.status,
      center: [center.lng, center.lat],
      radius: c.geo.state.accuracyRadius,
      located,
      buttons: document.querySelectorAll(".controls button, .toolbar button").length,
    };
  });
  const ok =
    /^\d+(\.\d+)?\u00a0(m|km)$/.test(r.scale) && r.credits.includes("国土地理院") &&
    Math.abs(r.zoomedIn - r.zoom - 1) < 1e-9 &&
    r.status === "active" && Math.abs(r.center[0] - 139.7) < 1e-6 && Math.abs(r.center[1] - 35.66) < 1e-6 && r.radius > 0 && r.located &&
    r.buttons >= 6;
  return { ok, ...r };
}

// The showcase's search (mbmap/search, no server): place names, coordinates in
// three forms (plane rectangular and UTM through mbmap/analysis), and the input
// box driven from the keyboard, each choice moving the map.
async function searchChecks(page) {
  const find = (query) =>
    page.evaluate(async (query) => {
      const s = window.__search;
      s.setQuery(query);
      await s.submit();
      return s.state.results.map((r) => ({ label: r.label, provider: r.provider, lng: r.lngLat.lng, lat: r.lngLat.lat, detail: r.detail ?? null }));
    }, query);
  const names = await find("とうきょう");
  const kanji = await find("東京");
  const decimal = await find("35.6586, 139.7454");
  const plane = await find("第IX系 X -35367.23 Y -5995.19");
  const utm = await find("54N 388708 3949480");
  const typed = page.locator("#search input, .react-search input").first();
  await typed.fill("東京タワー");
  await page.waitForFunction(() => !window.__search.state.loading && window.__search.state.results.length === 1 && window.__search.state.results[0].label === "東京タワー");
  // Keys that confirm a Japanese IME conversion are the IME's: neither the composing Enter nor
  // Safari's confirming one (keyCode 229) chooses a result.
  const imeIgnored = await page.evaluate(async () => {
    const input = document.querySelector("#search input, .react-search input");
    for (const init of [{ key: "Enter", isComposing: true }, { key: "Enter", keyCode: 229 }, { key: "ArrowDown", isComposing: true }]) {
      input.dispatchEvent(new KeyboardEvent("keydown", { ...init, bubbles: true, cancelable: true }));
    }
    await new Promise((r) => setTimeout(r, 300));
    const s = window.__search.state;
    return s.selected?.label !== "東京タワー" && s.active === -1 && s.open && !window.__map.isMoving();
  });
  await typed.press("ArrowDown");
  const moved = page.evaluate(() => window.__map.once("moveend"));
  await typed.press("Enter");
  await moved;
  const chosen = await page.evaluate(() => ({ label: window.__search.state.selected?.label, center: window.__map.getCenter(), open: window.__search.state.open }));
  const near = (r, lng, lat, tol) => r && Math.abs(r.lng - lng) < tol && Math.abs(r.lat - lat) < tol;
  const ok =
    names.length === 0 &&
    kanji.map((r) => r.label).join() === "東京駅,東京タワー,東京スカイツリー" && kanji.every((r) => r.provider === "地点") &&
    near(decimal[0], 139.7454, 35.6586, 1e-12) && decimal[0].provider === "座標" &&
    plane.length === 1 && plane[0].detail === "第IX系" && near(plane[0], 139.7671, 35.6812, 1e-6) &&
    utm.length === 1 && utm[0].detail === "UTM 54N" && near(utm[0], 139.77, 35.68, 0.01) &&
    imeIgnored && chosen.label === "東京タワー" && !chosen.open && near({ lng: chosen.center.lng, lat: chosen.center.lat }, 139.7454, 35.6586, 1e-3);
  return { ok, kanji, decimal: decimal[0], plane: plane[0], utm: utm[0], imeIgnored, chosen };
}

// The showcase's measurement: a line ended by a double click (no zoom, no identify) and an area
// finished from the panel reach geographiclib-geodesic's numbers to the bit; 「消す」 empties the overlay.
async function measureChecks(page) {
  // geographiclib in the page itself: engines' Math differ in the last bit now and then.
  await page.addScriptTag({ path: path.join(ROOT, "bench/node_modules/geographiclib-geodesic/geographiclib-geodesic.min.js") });
  // The numbers of the vertices placed, once the controller has them (vertices come at once, numbers from the worker).
  const measured = async (n, closed) => {
    await page.waitForFunction((n) => window.__measurement.state.positions.length === n && window.__measurement.state.finished, n);
    await page.waitForFunction((closed) => {
      const s = window.__measurement.state;
      const p = geodesic.Geodesic.WGS84.Polygon(!closed);
      for (const [lng, lat] of s.positions) p.AddPoint(lat, lng);
      const r = p.Compute(false, true);
      return s.length === r.perimeter && s.area === (closed ? Math.abs(r.area) : null) && s.segments.length === (closed ? s.positions.length : s.positions.length - 1);
    }, closed);
    return page.evaluate(() => window.__measurement.state);
  };
  const before = await page.evaluate(() => ({ zoom: window.__map.getZoom(), point: window.__identify.state.point }));
  await page.click("#measure button >> text=距離");
  await page.mouse.click(420, 160);
  await page.mouse.click(620, 200);
  await page.mouse.move(560, 300, { steps: 2 });
  await page.mouse.dblclick(520, 380);
  const line = await measured(3, false);
  const after = await page.evaluate(() => ({ zoom: window.__map.getZoom(), point: window.__identify.state.point, layers: window.__map.getStyle().layers.filter((l) => l.id.startsWith("mbmap-measure")).map((l) => l.id) }));
  const text = await page.evaluate(() => document.getElementById("measured").textContent);
  const profiled = await profileChecks(page, line.length);
  await page.click("#measure button >> text=面積");
  for (const [x, y] of [[420, 160], [620, 200], [520, 380]]) await page.mouse.click(x, y);
  await page.click("#measure button >> text=終える");
  const area = await measured(3, true);
  await page.click("#measure button >> text=消す");
  const cleared = await page.evaluate(async () => {
    await window.__map.once("idle");
    return { mode: window.__measurement.state.mode, features: window.__map.getStyle().sources["mbmap-measure"].data.features.length, dblclick: window.__map.doubleClickZoom.isEnabled(), profile: window.__profile.state.distances.length };
  });
  const sum = (a) => a.reduce((x, y) => x + y, 0);
  const ok =
    line.mode === "distance" && line.segments.length === 2 && Math.abs(sum(line.segments) - line.length) < 1e-6 &&
    area.mode === "area" && area.segments.length === 3 && area.area > 0 &&
    after.zoom === before.zoom && JSON.stringify(after.point) === JSON.stringify(before.point) && after.layers.length === 3 && text.includes(" m") &&
    cleared.mode === null && cleared.features === 0 && cleared.dblclick && cleared.profile === 0 && profiled.ok;
  return { ok, profiled, line: { mode: line.mode, length: line.length, segments: line.segments }, area: { mode: area.mode, perimeter: area.length, area: area.area, segments: area.segments }, after, text, cleared };
}

// The profile of the measured line (mbmap/ui over mbmap/geodesic and mbmap/analysis's sampleDem):
// samples along it to its length, heights at each, and the chart's pointer shown as a dot on the map.
async function profileChecks(page, length) {
  await page.waitForFunction(() => !window.__profile.state.loading && window.__profile.state.distances.length > 2, null, { timeout: 30000 });
  const s = await page.evaluate(() => window.__profile.state);
  const box = await page.locator("#profile svg").boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForFunction(() => window.__profile.state.active >= 0);
  const pointed = await page.evaluate(() => {
    const p = window.__profile.state;
    const at = window.__map.project({ lng: p.path[p.active][0], lat: p.path[p.active][1] });
    const dot = document.querySelector(".profile-dot");
    return { active: p.active, hidden: dot.hidden, transform: dot.style.transform, want: `translate(${at.x}px, ${at.y}px)`, caption: document.getElementById("profile").textContent };
  });
  const ascending = s.distances.every((d, i) => i === 0 || d > s.distances[i - 1]);
  const ok =
    s.distances[0] === 0 && ascending && Math.abs(s.distances.at(-1) - length) < 1e-6 && Math.abs(s.length - length) < 1e-6 &&
    s.elevations.length === s.path.length && s.elevations.every(Number.isFinite) && s.min <= s.max && s.error === null &&
    !pointed.hidden && pointed.transform === pointed.want && pointed.caption.includes("登り");
  return { ok, samples: s.distances.length, min: s.min, max: s.max, gain: s.gain, pointed };
}

// Whether a pin's `translate(xpx, ypx)` puts it at the 800 x 600 page's centre.
function atCentre(transform) {
  const m = /^translate\(([-\d.e]+)px, ([-\d.e]+)px\)$/.exec(transform ?? "");
  return !!m && Math.abs(Number(m[1]) - 400) < 0.01 && Math.abs(Number(m[2]) - 300) < 0.01;
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
    // 404s are expected (missing style, missing fixtures); so are the
    // rejections the element and style checks provoke.
    const expected = /404|mb-map: invalid|no layer "nope"|"gsi" is used by layer|expression sqrt|'nope' does not exist|sourceLayer parameter must be provided/;
    page.on("console", (m) => m.type() === "error" && !expected.test(m.text()) && errors.push(m.text()));
    await page.addInitScript(fakeGeolocation);
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
