// mbmap/3d's I3S layer on bench/npm/pages/i3s: the synthetic buildings (Draco, a PNG atlas) refine into their
// children up close and coarsen to the root afar, a click gives attributes; the synthetic point cloud
// (PCSL, LEPCC) refines by density; the buildings as an SLPK give the same nodes and attributes.
import { commonestShare } from "./pixels.mjs";

export async function i3sChecks(page) {
  await page.waitForFunction(() => window.__loaded !== undefined);
  const close = await page.evaluate(async () => {
    await window.__layer.ready;
    await window.__settled();
    return window.__layer.selected.map((t) => t.path).sort();
  });
  const blank = await commonestShare(page);
  // A colored building (node 4) and a textured one (node 3) in this view.
  const picked = await page.evaluate(async () => [await window.__layer.queryFeature({ x: 495, y: 350 }), await window.__layer.queryFeature({ x: 195, y: 290 }), await window.__layer.queryFeature({ x: 400, y: 300 })]);
  const far = await page.evaluate(async () => {
    window.__map.jumpTo({ zoom: 14, pitch: 0 });
    await window.__settled();
    return window.__layer.selected.map((t) => t.path).sort();
  });
  const points = await page.evaluate(async () => {
    const map = window.__map;
    map.removeLayer("buildings");
    const { i3sLayer } = await import("mbmap/3d");
    const layer = i3sLayer({ id: "points", url: new URL("./pcsl/layers/0/layer.json", location.href).href, pointSize: 3 });
    map.addLayer(layer);
    window.__layer = layer;
    await layer.ready;
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 17, pitch: 50, bearing: -20 });
    await window.__settled();
    const close = window.__layer.selected.map((t) => t.path).sort();
    return { close };
  });
  const pointsBlank = await commonestShare(page);
  const pointsFar = await page.evaluate(async () => {
    window.__map.jumpTo({ zoom: 14, pitch: 0 });
    await window.__settled();
    return window.__layer.selected.map((t) => t.path).sort();
  });
  // The same buildings packed as an SLPK (bench/i3s/slpk-write.mjs), read by range requests.
  const slpk = await page.evaluate(async () => {
    const map = window.__map;
    map.removeLayer("points");
    const { i3sLayer } = await import("mbmap/3d");
    const layer = i3sLayer({ id: "slpk", url: new URL("./set.slpk", location.href).href });
    map.addLayer(layer);
    window.__layer = layer;
    await layer.ready;
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 17, pitch: 50, bearing: -20 });
    await window.__settled();
    return { close: window.__layer.selected.map((t) => t.path).sort(), hit: await window.__layer.queryFeature({ x: 495, y: 350 }) };
  });
  const props = (hit) => hit && typeof hit.properties.OBJECTID === "number" && typeof hit.properties.name === "string" && typeof hit.properties.height === "number";
  const ok =
    JSON.stringify(close) === JSON.stringify(["1", "2", "3", "4"]) && blank < 0.9 &&
    picked[0]?.tile === "4" && props(picked[0]) && picked[1]?.tile === "3" && props(picked[1]) && picked[2] === null &&
    JSON.stringify(far) === JSON.stringify(["0"]) &&
    points.close.length === 4 && !points.close.includes("0") && pointsBlank < 0.95 && JSON.stringify(pointsFar) === JSON.stringify(["0"]) &&
    JSON.stringify(slpk.close) === JSON.stringify(close) && slpk.hit?.properties.OBJECTID === picked[0]?.properties.OBJECTID;
  return [ok, { close, blank, picked, far, points, pointsBlank, pointsFar, slpk }];
}
