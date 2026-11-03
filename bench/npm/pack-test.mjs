// Checks the examples built on the packed package in Chromium; without the
// fixtures tiles 404 and maps load empty, so CI runs it too.
// Usage: node npm/pack-test.mjs [--screenshots=dir]
import path from "node:path";
import { chromium } from "playwright";
import { serve } from "../lib/serve.mjs";
import { prepareExamples } from "./prepare.mjs";
import { fakeGeolocation } from "../lib/fake-geolocation.mjs";
import { clusterChecks } from "./checks/clusters.mjs";
import { imageChecks } from "./checks/images.mjs";
import { drawChecks, editChecks, measureChecks, splitChecks } from "./checks/geo-tools.mjs";
import { mediaChecks } from "./checks/media.mjs";
import { customChecks } from "./checks/custom.mjs";
import { cameraChecks } from "./checks/camera.mjs";
import { controlChecks } from "./checks/controls.mjs";
import { atCentre } from "./checks/pixels.mjs";
import { queryChecks } from "./checks/query.mjs";
import { searchChecks } from "./checks/search.mjs";
import { stateChecks } from "./checks/state.mjs";
import { styleChecks } from "./checks/style.mjs";
import { tileSourceChecks } from "./checks/tile-sources.mjs";
import { trackExportChecks } from "./checks/track-export.mjs";
import { crumb, mapState, trail } from "./checks/step.mjs";

const shots = process.argv.find((a) => a.startsWith("--screenshots="))?.split("=")[1];
await prepareExamples();

const ATTRIBUTION = "国土地理院ベクトルタイル提供実験";

// Where each check's page is.
const PAGES = {
  npm: "bench/npm/pages/npm/",
  element: "bench/npm/pages/element/",
  geojson: "bench/npm/pages/geojson/",
  analysis: "bench/npm/pages/analysis/",
  media: "bench/npm/pages/media/",
  custom: "bench/npm/pages/custom/",
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
        new Map({ container: div, style: { version: 8, sources: {}, layers: [{ id: "x", type: "line", paint: { "line-width": ["number-format", 2, {}] } }] } });
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
      r.thrown === "mbmap: style: layers[0].paint.line-width: unsupported: expression number-format" &&
      r.lazy &&
      r.workerRefused.startsWith("mbmap: the worker must be a same-origin http(s) URL") &&
      r.leftovers === 0;
    crumb("queryChecks");
    const query = await queryChecks(page);
    crumb("stateChecks");
    const state = await stateChecks(page);
    crumb("tileSourceChecks");
    const tiles = await tileSourceChecks(page);
    crumb("trackExportChecks");
    const exported = await trackExportChecks(page);
    crumb("styleChecks");
    const style = await styleChecks(page, requests);
    crumb("cameraChecks");
    const camera = await cameraChecks(page);
    crumb("imageChecks");
    const images = await imageChecks(page);
    return [
      ok && query.ok && state.ok && tiles.ok && exported.ok && style.ok && camera.ok && images.ok,
      { ...r, query, state, tiles, exported, style, camera, images },
    ];
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
      // Split and merge on GeoJSON features, mixed kinds refused; too many DEM tiles refused before any fetch.
      const { splitFeatures, mergeFeatures, loadDem: loadDem2 } = await import("mbmap/analysis");
      const square = { properties: { name: "s" }, geometry: { type: "Polygon", coordinates: [[[0, 0], [2, 0], [2, 2], [0, 2], [0, 0]]] } };
      const halves = await splitFeatures([square], { type: "LineString", coordinates: [[1, -1], [1, 3]] });
      const whole = await mergeFeatures(halves);
      const mixed = await mergeFeatures([square, { properties: {}, geometry: { type: "Point", coordinates: [5, 5] } }]).then(() => "", (e) => e.message);
      const tooMany = await loadDem2("/bench/fixtures/gsi-dem/{z}/{x}/{y}.png", { zoom: 24, bounds: [-180, -85, 180, 85], encoding: "gsi" }).then(() => "", (e) => e.message);
      const geometry = {
        halves: halves.map((f) => [f.geometry.type, f.properties.name]),
        whole: [whole.geometry.type, whole.properties.name],
        mixed,
        tooMany,
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
      /unsupported projection: \+proj=geos/.test(r.geometry.badProj) &&
      JSON.stringify(r.geometry.halves) === JSON.stringify([["Polygon", "s"], ["Polygon", "s"]]) &&
      JSON.stringify(r.geometry.whole) === JSON.stringify(["Polygon", "s"]) &&
      /only features of one kind/.test(r.geometry.mixed) && /too many for one grid/.test(r.geometry.tooMany);
    return [ok, { loaded, ...r }];
  },

  async media(page, requests) {
    return mediaChecks(page, requests);
  },

  async custom(page) {
    return customChecks(page);
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
// camera, the destinations' pins on their places, the view saved as a PNG, and the stations' clusters.
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
  crumb("measureChecks");
  const measured = await measureChecks(page);
  crumb("drawChecks");
  const drew = await drawChecks(page);
  crumb("editChecks");
  const edited = await editChecks(page);
  crumb("splitChecks");
  const cut = await splitChecks(page);
  crumb("clusterChecks");
  const clustered = await clusterChecks(page);
  crumb("showcase: 3D");
  await page.click("#modes button >> text=3D");
  await page.waitForFunction(() => window.__map && window.__map.getPitch() === 60 && !window.__map.isMoving(), null, { timeout: 30000 });
  const tilted = await page.evaluate(() => ({ pitch: window.__map.getPitch(), bearing: window.__map.getBearing() }));
  await page.click("#destinations button >> text=大阪駅");
  await page.waitForFunction(() => Math.abs(window.__map.getCenter().lng - 135.4959) < 1e-9 && !window.__map.isMoving(), null, { timeout: 30000 });
  await page.waitForFunction(() => window.__described.near.includes("大阪駅"));
  const osaka = await page.evaluate(() => window.__described);
  const shown = await panel();
  const osakaPin = await pin("大阪駅");
  crumb("showcase: save");
  await page.click("#save");
  await page.waitForFunction(() => window.__saved, null, { timeout: 30000 });
  const saved = await page.evaluate(() => window.__saved);
  crumb("controlChecks");
  const controls = await controlChecks(page);
  crumb("searchChecks");
  const searched = await searchChecks(page);
  crumb("showcase: layers, marker, basemaps");
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
      // The custom layer comes back under the places after each new style.
      ring: map.getLayer("radius-ring")?.type === "custom" && map.getLayersOrder().indexOf("radius-ring") === map.getLayersOrder().indexOf("places") - 1,
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
    styled.photo.layers.includes("photo") && !styled.photo.layers.includes("road") && styled.photo.layers.at(-1) === "places-label" && styled.photo.marker === "印 1" && styled.back && styled.ring &&
    first.near.includes("東京駅") && !first.near.includes("新宿駅") &&
    first.plane.zone === "第IX系" &&
    Math.abs(first.plane.x - -5995.185) < 0.01 && Math.abs(first.plane.y - -35367.23) < 0.01 &&
    tilted.pitch === 60 && tilted.bearing === -20 &&
    osaka.plane.zone === "第VI系" &&
    shown.includes("135.49590") && shown.includes("第VI系") &&
    atCentre(tokyoPin) && atCentre(osakaPin) &&
    saved.type === "image/png" && saved.size > 0 && controls.ok && searched.ok && measured.ok && drew.ok && edited.ok && cut.ok && clustered.ok;
  return [ok, { first, picked, identified, coordinates, hovered, tilted, osaka: osaka.near, shown, styled, tokyoPin, osakaPin, saved, controls, searched, measured, drew, edited, cut, clustered }];
}

async function engineStarted(page) {
  const r = await page.evaluate(() => ({ frames: window.__mbmap.map_frame_count(window.__map) }));
  return [r.frames > 0, r];
}

const { server, origin } = await serve();
// Metal only exists on macOS; elsewhere (CI) Chromium falls back to SwiftShader.
// Each example's checks take well under a minute; one that runs longer has hung.
const CHECK_TIMEOUT = 180_000;
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
    const expected = /404|mb-map: invalid|no layer "nope"|"gsi" is used by layer|expression number-format|'nope' does not exist|sourceLayer parameter must be provided|image named "swatch" already exists|width \* height \* 4 bytes|media must be http|missing required method/;
    page.on("console", (m) => m.type() === "error" && !expected.test(m.text()) && errors.push(m.text()));
    await page.addInitScript(fakeGeolocation);
    await page.goto(`${origin}/${PAGES[example]}`);
    await page.waitForFunction(() => window.__loaded, null, { timeout: 30000 });
    if (shots) await page.screenshot({ path: path.join(shots, `${example}.png`) });
    // A check that hangs (an event that never comes) fails after CHECK_TIMEOUT instead of holding CI,
    // saying which steps it entered last and what the map was doing.
    trail.length = 0;
    crumb(example);
    let timer;
    const late = new Promise((resolve) => {
      timer = setTimeout(async () => {
        resolve([false, { timedOut: `no answer after ${CHECK_TIMEOUT / 1000} s`, steps: trail.slice(), map: await mapState(page) }]);
      }, CHECK_TIMEOUT);
    });
    const run = check(page, requests).catch(async (e) => [false, { failed: e.message, steps: trail.slice(), map: await mapState(page) }]);
    const [ok, details] = await Promise.race([run, late]);
    clearTimeout(timer);
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
