// mbmap/3d's I3S layer on bench/npm/pages/i3s: the synthetic 3DObject layer (bench/i3s/synthetic.mjs) is
// refined into its four children up close (Draco buffers, a PNG atlas on two of them) and coarsened to
// its root from afar; a click gives the building's attributes (OBJECTID, name, height).
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
  const props = (hit) => hit && typeof hit.properties.OBJECTID === "number" && typeof hit.properties.name === "string" && typeof hit.properties.height === "number";
  const ok =
    JSON.stringify(close) === JSON.stringify(["1", "2", "3", "4"]) && blank < 0.9 &&
    picked[0]?.tile === "4" && props(picked[0]) && picked[1]?.tile === "3" && props(picked[1]) && picked[2] === null &&
    JSON.stringify(far) === JSON.stringify(["0"]);
  return [ok, { close, blank, picked, far }];
}
