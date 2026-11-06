// mbmap/services on bench/npm/pages/services: a WMTS from its capabilities draws the GSI tiles it
// names pixel for pixel, a WMS layer by GetMap in EPSG:3857 keeping the endpoint's parameters, and
// exceptions, malformed documents, unknown layers and non-http URLs are refused with the reason.
import { decodePng } from "../../lib/png.mjs";

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
    loaded.includes("services.js") && loaded.includes("wmts.xml") && loaded.includes("wms.xml");
  return [ok, { ...r, same, drawn, getMaps: getMaps.length, first, loaded: [...new Set(loaded)] }];
}
