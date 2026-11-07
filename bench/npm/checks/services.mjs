// mbmap/services on bench/npm/pages/services: a WMTS and an ArcGIS VectorTileServer draw the GSI tiles
// they name pixel for pixel, a WMS layer by GetMap in EPSG:3857 keeping the endpoint's parameters, and
// exceptions, malformed documents, unknown layers and non-http URLs are refused with the reason.
import { existsSync } from "node:fs";
import path from "node:path";
import { decodePng } from "../../lib/png.mjs";
import { ROOT } from "../../lib/root.mjs";

export async function servicesChecks(page, requests) {
  const shot = async () => decodePng(await page.screenshot({ clip: { x: 0, y: 0, width: 600, height: 400 } })).rgba;
  const before = await shot();
  const r = await page.evaluate(async () => {
    const services = await import("mbmap/services");
    const map = window.__map;
    const fails = (p) => p.then(() => "", (e) => e.message);
    const failsNow = (f) => {
      try {
        f();
        return "";
      } catch (e) {
        return e.message;
      }
    };
    const wmts = await services.getCapabilities("./wmts.xml", "WMTS");
    const tiled = services.wmtsSource(wmts, { layer: "std" });
    map.removeLayer("gsi");
    map.addSource("wmts", tiled);
    map.addLayer({ id: "wmts", type: "raster", source: "wmts" });
    await map.once("idle");
    window.__wmts = { source: tiled, title: wmts.title, zooms: services.mercatorZooms(wmts.tileMatrixSets[0]) };

    const wms = await services.getCapabilities("./wms.xml", "WMS");
    const layer = services.allLayers(wms.layers).find((l) => l.name === "std");
    const mapped = services.wmsSource(wms, { layers: "std" });
    return {
      wmts: window.__wmts,
      wms: { source: mapped, layer: { crs: layer.crs, queryable: layer.queryable, attribution: layer.attribution, styles: layer.styles.map((s) => s.name) } },
      refusals: {
        exception: await fails(services.getCapabilities("./exception.xml", "WMS")),
        malformed: failsNow(() => services.readWMSCapabilities("<WMS_Capabilities")),
        notWms: failsNow(() => services.readWMSCapabilities("<Capabilities/>")),
        unknown: failsNow(() => services.wmsSource(wms, { layers: "nope" })),
        refused: await fails(services.getCapabilities("data:text/xml,<a/>", "WMS")),
        missing: await fails(services.getCapabilities("./missing.xml", "WMTS")),
      },
    };
  });
  const wmtsShot = await shot();
  const same = before.length === wmtsShot.length && before.every((v, i) => v === wmtsShot[i]);

  await page.evaluate(async () => {
    const map = window.__map;
    map.removeLayer("wmts");
    const services = await import("mbmap/services");
    map.addSource("wms", services.wmsSource(await services.getCapabilities("./wms.xml", "WMS"), { layers: "std" }));
    map.addLayer({ id: "wms", type: "raster", source: "wms" });
    await map.once("idle");
  });
  // An ArcGIS VectorTileServer (bench/npm/pages/services/arcgis/..., its tiles the GSI vector
  // fixtures): its style made absolute, and its root.json read as is, draw what a plain source does.
  const top = async () => decodePng(await page.screenshot({ clip: { x: 0, y: 0, width: 600, height: 360 } })).rgba;
  const restyle = (style) => page.evaluate(async (s) => {
    const map = window.__map;
    const services = await import("mbmap/services");
    map.setStyle(s === "arcgis" ? await services.arcgisStyle("./arcgis/rest/services/Test/VectorTileServer") : s);
    await map.once("idle");
    return s === "arcgis" ? map.getStyle().sources.esri : null;
  }, style);
  const root = await (await fetch(new URL("arcgis/rest/services/Test/VectorTileServer/resources/styles/root.json", page.url()))).json();
  await restyle({ ...root, sources: { esri: { type: "vector", tiles: ["../../../fixtures/gsi-bvmap/{z}/{x}/{y}.pbf"], minzoom: 14, maxzoom: 14 } } });
  const plain = await top();
  const esriSource = await restyle("arcgis");
  const esri = await top();
  await restyle("./arcgis/rest/services/Test/VectorTileServer/resources/styles/root.json");
  const asIs = await top();
  const equal = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
  // CI has no fixtures: the tiles 404 and all three maps show the background alone.
  const fixtures = existsSync(path.join(ROOT, "bench/fixtures/gsi-bvmap/14"));
  const vector = {
    fixtures,
    source: esriSource,
    same: equal(plain, esri),
    asIs: equal(plain, asIs),
    drawn: new Set(Array.from({ length: plain.length / 4 }, (_, i) => plain[i * 4] * 65536 + plain[i * 4 + 1] * 256 + plain[i * 4 + 2])).size > 2,
  };

  // followView: an OGC API collection's two pages (bench/npm/pages/services/ogc) fill a GeoJSON source
  // for the view, asked again after a move and no more once stopped.
  const asked = () => requests.filter((u) => /\/ogc\/items\.json/.test(u)).length;
  const followed = await page.evaluate(async () => {
    const map = window.__map;
    const services = await import("mbmap/services");
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 13 });
    map.setStyle({ version: 8, sources: { view: { type: "geojson", data: { type: "FeatureCollection", features: [] } } }, layers: [
      { id: "bg", type: "background", paint: { "background-color": "#ffffff" } },
      { id: "view", type: "circle", source: "view", paint: { "circle-radius": 8, "circle-color": "#ff0000" } },
    ] });
    await map.once("idle");
    const bounds = [];
    const loaded = map.once("sourcedata");
    const stop = services.followView(map, "view", (b, signal) => {
      bounds.push(b);
      return services.ogcFeatures("./ogc/items.json", { bbox: b, limit: 2, signal });
    });
    await loaded;
    await map.once("idle");
    const data = map.getSource("view").getData ? await map.getSource("view").getData() : null;
    const at = map.project([139.7709, 35.6918]);
    return { stop: (window.__stopFollow = stop) && true, features: data?.features?.map((f) => f.id), bounds: bounds.length, first: bounds[0], at };
  });
  const kanda = await page.screenshot({ clip: { x: Math.round(followed.at.x), y: Math.round(followed.at.y), width: 1, height: 1 } }).then((b) => [...decodePng(b).rgba.slice(0, 3)]);
  const askedBefore = asked();
  await page.evaluate(async () => {
    const map = window.__map;
    map.jumpTo({ center: [139.77, 35.69] });
    await map.once("idle");
    await new Promise((r) => setTimeout(r, 200));
    window.__stopFollow();
    map.jumpTo({ center: [139.76, 35.68] });
    await map.once("idle");
  });
  const follow = { ...followed, kanda, moved: askedBefore > 0 && asked() > askedBefore, stopped: asked() };
  await new Promise((r) => setTimeout(r, 300));
  follow.stillStopped = asked() === follow.stopped;

  const getMaps = requests.filter((u) => /REQUEST=GetMap/.test(u)).map((u) => Object.fromEntries(new URL(u).searchParams));
  const wmsShot = await shot();
  const drawn = wmsShot.some((v, i) => i % 4 < 3 && v !== 255);
  const first = getMaps[0] ?? {};
  const bbox = (first.BBOX ?? "").split(",").map(Number);
  const loaded = requests.map((u) => u.split("/").pop().split("?")[0]).filter((n) => /services|\.xml$/.test(n));
  const ok =
    same &&
    r.wmts.source.minzoom === 0 && r.wmts.source.maxzoom === 14 && r.wmts.title === "地理院タイル（標準地図）" &&
    /\/bench\/fixtures\/gsi-std\/\{z\}\/\{x\}\/\{y\}\.png$/.test(r.wmts.source.tiles[0]) &&
    JSON.stringify(r.wms.layer.crs) === JSON.stringify(["EPSG:4326", "EPSG:3857"]) && r.wms.layer.queryable &&
    r.wms.layer.attribution?.title === "国土地理院" && r.wms.source.attribution === "国土地理院" &&
    JSON.stringify(r.wms.source.bounds) === JSON.stringify([139.74, 35.66, 139.8, 35.7]) &&
    drawn && getMaps.length > 0 &&
    first.map === "test" && first.SERVICE === "WMS" && first.LAYERS === "std" && first.CRS === "EPSG:3857" && first.VERSION === "1.3.0" &&
    first.WIDTH === "256" && bbox.length === 4 && bbox.every(Number.isFinite) &&
    /Invalid layer\(s\)/.test(r.refusals.exception) && /not well-formed/.test(r.refusals.malformed) && /not a WMS capabilities/.test(r.refusals.notWms) &&
    /no layer named nope/.test(r.refusals.unknown) && /must be an http\(s\) URL/.test(r.refusals.refused) && /HTTP 404/.test(r.refusals.missing) &&
    loaded.includes("services.js") && loaded.includes("wmts.xml") && loaded.includes("wms.xml") &&
    vector.same && vector.asIs && (vector.drawn || !fixtures) &&
    /\/bench\/fixtures\/gsi-bvmap\/\{z\}\/\{x\}\/\{y\}\.pbf$/.test(vector.source?.tiles?.[0]) &&
    vector.source.minzoom === 14 && vector.source.maxzoom === 14 && vector.source.attribution === "国土地理院ベクトルタイル提供実験" &&
    JSON.stringify(follow.features) === JSON.stringify(["tokyo", "yurakucho", "kanda"]) && follow.bounds >= 1 && follow.first.length === 4 &&
    follow.kanda[0] > 200 && follow.kanda[1] < 80 && follow.moved && follow.stillStopped;
  return [ok, { ...r, same, drawn, vector, follow, getMaps: getMaps.length, first, loaded: [...new Set(loaded)] }];
}
