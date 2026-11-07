// mbmap/services on bench/npm/pages/services: WMTS, ArcGIS VectorTileServer and WMS layers (tiled, one image of the
// view, or reprojected from EPSG:4326) draw what they name, features come from f=pbf, f=json, GetFeatureInfo and
// identify, and exceptions, malformed documents, unknown layers and non-http URLs are refused with the reason.
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

  // arcgisFeatures on a static FeatureServer (bench/npm/pages/services/arcgis/.../FeatureServer): layer 0
  // lists PBF, so its three stations come as f=pbf, layer 1 only JSON; both read by services.wasm.
  const features = await page.evaluate(async () => {
    const services = await import("mbmap/services");
    const layer = (n) => `./arcgis/rest/services/Test/FeatureServer/${n}`;
    const pbf = await services.arcgisFeatures(layer(0));
    const json = await services.arcgisFeatures(layer(1));
    const refused = await services.arcgisFeatures(layer(0), { format: "json" }).then(() => "", (e) => e.message);
    return { pbf, json, refused };
  });
  const near = (a, b) => a.length === b.length && a.every((v, i) => Math.abs(v - b[i]) < 1e-9);
  const esriOk =
    JSON.stringify(features.pbf.features.map((f) => [f.id, f.properties.name])) === JSON.stringify([[1, "東京"], [2, "有楽町"], [3, "神田"]]) &&
    near(features.pbf.features[2].geometry.coordinates, [139.7709, 35.6918]) &&
    features.json.features.length === 1 && features.json.features[0].id === 1 && features.json.features[0].properties.name === "丸の内" &&
    features.json.features[0].geometry.type === "Polygon" && features.json.features[0].geometry.coordinates.length === 2 &&
    near(features.json.features[0].geometry.coordinates[0][1], [139.765, 35.68]) &&
    /malformed ArcGIS JSON/.test(features.refused) &&
    requests.some((u) => /\/query\?.*f=pbf/.test(u)) && requests.some((u) => /\/query\?.*f=json/.test(u));

  const getMaps = requests.filter((u) => /REQUEST=GetMap/.test(u)).map((u) => Object.fromEntries(new URL(u).searchParams));
  const wmsShot = await shot();
  const drawn = wmsShot.some((v, i) => i % 4 < 3 && v !== 255);
  // followImage keeps an image source on one GetMap of the view (the static PNG of wms.xml); GetFeatureInfo
  // (info.json) and a MapServer's identify (arcgis/.../MapServer/identify) answer a click.
  const single = await page.evaluate(async () => {
    const map = window.__map;
    const services = await import("mbmap/services");
    map.setStyle({ version: 8, sources: {}, layers: [{ id: "bg", type: "background", paint: { "background-color": "#ffffff" } }] });
    await map.once("idle");
    const caps = await services.getCapabilities("./wms.xml", "WMS");
    const stop = services.followImage(map, "single", services.wmsImage(caps, { layers: "std" }), { pixelRatio: 1 });
    map.addLayer({ id: "single", type: "raster", source: "single" });
    await map.once("idle");
    const coordinates = map.getStyle().sources.single?.coordinates;
    const bounds = map.getBounds();
    stop();
    const at = [139.7671, 35.6812];
    const info = await services.wmsFeatureInfo(caps, { layers: "std" }, at, 14);
    const identified = await services.arcgisIdentify("./arcgis/rest/services/Test/MapServer", at, 14);
    return { coordinates, bounds: [bounds.getWest(), bounds.getSouth(), bounds.getEast(), bounds.getNorth()], info, identified };
  });
  const singleShot = await shot();
  const imageMap = requests.filter((u) => /REQUEST=GetMap/.test(u) && !/WIDTH=256&/.test(u)).map((u) => Object.fromEntries(new URL(u).searchParams))[0] ?? {};
  const corners = single.coordinates ?? [];
  const singleOk =
    // CI has no fixtures: the GetMap PNG 404s and the image is not drawn.
    (singleShot.some((v, i) => i % 4 < 3 && v !== 255) || !fixtures) &&
    Number(imageMap.WIDTH) > 256 && Number(imageMap.HEIGHT) > 256 && imageMap.BBOX?.split(",").length === 4 &&
    corners.length === 4 && Math.abs(corners[0][0] - single.bounds[0]) < 1e-6 && Math.abs(corners[0][1] - single.bounds[3]) < 1e-6 &&
    single.info.features?.[0]?.properties?.name === "東京駅" &&
    requests.some((u) => /info\.json\?.*REQUEST=GetFeatureInfo.*INFO_FORMAT=application%2Fgeo%2Bjson/.test(u)) &&
    single.identified.features?.[0]?.id === "1" && single.identified.features[0].layer?.name === "Stations" &&
    JSON.stringify(single.identified.features[0].geometry) === JSON.stringify({ type: "Point", coordinates: [139.7671, 35.6812] });

  // A WMTS in EPSG:4326 (wmts-4326.xml: the west half blue, the east green) becomes a reprojected source.
  const geo = await page.evaluate(async () => {
    const map = window.__map;
    const services = await import("mbmap/services");
    const source = services.wmtsSource(await services.getCapabilities("./wmts-4326.xml", "WMTS"), { layer: "halves" });
    map.jumpTo({ center: [0, 0], zoom: 1 });
    map.setStyle({ version: 8, sources: { geo: source }, layers: [{ id: "bg", type: "background", paint: { "background-color": "#ffffff" } }, { id: "geo", type: "raster", source: "geo" }] });
    await map.once("idle");
    return { type: source.type, crs: source.crs, template: source.grid?.template, west: map.project([-60, 0]), east: map.project([60, 0]) };
  });
  const pixel = async ({ x, y }) => [...decodePng(await page.screenshot({ clip: { x: Math.round(x), y: Math.round(y), width: 1, height: 1 } })).rgba.slice(0, 3)];
  geo.colors = [await pixel(geo.west), await pixel(geo.east)];
  const geoOk = geo.type === "reprojected" && geo.crs === 4326 && /\/geo\/\{TileMatrix\}\/\{TileRow\}\/\{TileCol\}\.png$/.test(geo.template) &&
    JSON.stringify(geo.colors) === JSON.stringify([[0, 0, 255], [0, 255, 0]]);

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
    follow.kanda[0] > 200 && follow.kanda[1] < 80 && follow.moved && follow.stillStopped &&
    esriOk && loaded.includes("services-worker.js") && loaded.includes("services.wasm") && singleOk &&
    geoOk && requests.some((u) => /data-reproject\.js$/.test(u));
  return [ok, { ...r, same, drawn, vector, follow, geo: { ok: geoOk, ...geo }, single: { ok: singleOk, request: imageMap, coordinates: corners, bounds: single.bounds, info: single.info, identified: single.identified }, features: { ok: esriOk, refused: features.refused, pbf: features.pbf.features.length }, getMaps: getMaps.length, first, loaded: [...new Set(loaded)] }];
}
