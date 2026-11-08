// mbmap/3d's tiles layer on bench/npm/pages/tiles: the synthetic b3dm tileset (bench/tiles/synthetic.mjs)
// (a cmpt of b3dm and instanced i3dm trees among them) is refined into its four tiles up close, coarsened to its root from afar, and drawn on the globe;
// PLATEAU's Draco-compressed buildings around Tokyo Station are refined and drawn; a click picks a
// feature with its batch table's properties; a pnts and a glTF of points (tiles/points) are drawn and picked.
import { decodePng } from "../../lib/png.mjs";
import { commonestShare } from "./pixels.mjs";

/** The shares of the screen's pixels near the points' red, blue and green. */
async function pointPixels(page) {
  const { rgba } = decodePng(await page.screenshot());
  const count = { red: 0, blue: 0, green: 0 };
  const near = (i, c) => Math.abs(rgba[i] - c[0]) < 40 && Math.abs(rgba[i + 1] - c[1]) < 40 && Math.abs(rgba[i + 2] - c[2]) < 40;
  for (let i = 0; i < rgba.length; i += 4) {
    if (near(i, [220, 40, 40])) count.red++;
    else if (near(i, [40, 70, 220])) count.blue++;
    else if (near(i, [30, 170, 60])) count.green++;
  }
  const n = rgba.length / 4;
  return { red: count.red / n, blue: count.blue / n, green: count.green / n };
}

export async function tilesChecks(page) {
  await page.evaluate(() => window.__layer.ready);
  await page.evaluate(() => window.__settled());
  const close = await page.evaluate(() => window.__layer.selected.map((t) => t.path).sort());
  // A block under the screen's center, with its batch table's height; nothing in the sky.
  const picked = await page.evaluate(async () => [await window.__layer.queryFeature({ x: 400, y: 300 }), await window.__layer.queryFeature({ x: 5, y: 5 })]);
  const closeBlank = await commonestShare(page);
  // The first quadrant is a cmpt with a row of instanced trees (i3dm); one is under (361, 312) here.
  const tree = await page.evaluate(async () => {
    window.__map.jumpTo({ center: [139.7652, 35.6774], zoom: 18, pitch: 55, bearing: 0 });
    await window.__settled();
    return window.__layer.queryFeature({ x: 361, y: 312 });
  });
  await page.evaluate(async () => {
    window.__map.jumpTo({ zoom: 12, pitch: 0 });
    await window.__settled();
  });
  const far = await page.evaluate(() => window.__layer.selected.map((t) => t.path).sort());
  await page.evaluate(async () => {
    window.__map.setProjection({ type: "globe" });
    window.__map.jumpTo({ zoom: 14, pitch: 45 });
    await window.__settled();
  });
  const globe = await page.evaluate(() => window.__layer.selected.map((t) => t.path).sort());
  const globeBlank = await commonestShare(page);
  // The fixture holds the tiles around Tokyo Station; heights are above the ellipsoid (geoid +36.7 m).
  const plateau = await page.evaluate(async () => {
    const url = new URL("/bench/fixtures/plateau-chiyoda/tileset.json", location.href).href;
    // CI's small pages run without the fixtures, as the terrain check does.
    if (!(await fetch(url, { method: "HEAD" })).ok) return { skipped: "no fixtures" };
    const map = window.__map;
    map.setProjection(null);
    map.removeLayer("blocks");
    const layer = window.__tilesLayer({ id: "plateau", url, height: -36.7 });
    map.addLayer(layer);
    window.__layer = layer;
    await layer.ready;
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 17, pitch: 50, bearing: -20 });
    await window.__settled();
    const hit = await layer.queryFeature({ x: 400, y: 300 });
    return { tiles: layer.selected.length, ready: layer.selected.every((t) => t.state === "ready"), city: hit?.properties.city_code, gml: typeof hit?.properties.gml_id };
  });
  const plateauBlank = await commonestShare(page);
  // Points: a red and blue checkerboard (pnts, `kind` per point) inside a green ring of glTF points.
  const points = await page.evaluate(async () => {
    const map = window.__map;
    for (const id of ["blocks", "plateau"]) if (map.getLayer(id)) map.removeLayer(id);
    map.setProjection(null);
    const layer = window.__tilesLayer({ id: "points", url: new URL("./points/tileset.json", location.href).href, pointSize: 6 });
    map.addLayer(layer);
    window.__layer = layer;
    await layer.ready;
    map.jumpTo({ center: [139.7655, 35.6795], zoom: 18, pitch: 0, bearing: 0 });
    await window.__settled();
    const hit = await layer.queryFeature({ x: 400, y: 300 });
    const ring = await layer.queryFeature({ x: 400 + 185, y: 300 });
    return { tiles: layer.selected.map((t) => t.path).sort(), kind: hit?.properties.kind, id: hit?.id, ring: ring?.tile };
  });
  const pixels = await pointPixels(page);
  const ok =
    JSON.stringify(close) === JSON.stringify(["r/0", "r/1", "r/2", "r/3"]) && closeBlank < 0.8 &&
    close.includes(picked[0]?.tile) && typeof picked[0]?.properties.height === "number" && picked[1] === null &&
    tree?.tile === "r/0" && tree.properties.kind === "tree" &&
    JSON.stringify(far) === JSON.stringify(["r"]) &&
    globe.length > 0 && globeBlank < 0.99 &&
    (plateau.skipped !== undefined || (plateau.tiles >= 10 && plateau.ready && plateauBlank < 0.6 && plateau.city === "13101" && plateau.gml === "string")) &&
    JSON.stringify(points.tiles) === JSON.stringify(["r", "r/0"]) && ["red", "blue"].includes(points.kind) && points.ring === "r/0" &&
    pixels.red > 0.02 && pixels.blue > 0.02 && pixels.green > 0.001;
  return [ok, { close, picked, tree, closeBlank, far, globe, globeBlank, plateau, plateauBlank, points, pixels }];
}
