// Custom layers on bench/npm/pages/custom: the box drawn through MapLibre's prelude sits under the
// square (`beforeId`) and over it once moved, the GL state it breaks is restored, `render` gets
// MapLibre's options, a "3d" layer has the depth test, and removing calls `onRemove`.
import { near, pixel } from "./pixels.mjs";

const [blue, red, white] = [[0, 0, 255], [255, 0, 0], [255, 255, 255]];

export async function customChecks(page) {
  await page.waitForFunction(() => window.__box.calls.render > 0, null, { timeout: 30000 });
  const frame = () => page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
  await frame();
  const at = await page.evaluate(() => Object.fromEntries([["box", [-5, 0]], ["both", [8, 0]], ["square", [13, 0]], ["out", [25, 0]]].map(([k, p]) => [k, window.__map.project(p)])));
  const look = async () => Object.fromEntries(await Promise.all(Object.entries(at).map(async ([k, p]) => [k, await pixel(page, p.x, p.y)])));
  const under = await look();

  const r = await page.evaluate(async () => {
    const map = window.__map;
    const box = window.__box;
    const o = box.options;
    const m = o.defaultProjectionData.mainMatrix;
    // The center (Mercator 0.5, 0.5) goes to the middle of clip space.
    const c = [0, 1, 3].map((k) => m[k] * 0.5 + m[4 + k] * 0.5 + m[12 + k]);
    const before = box.calls.render;
    map.triggerRepaint();
    await new Promise((done) => map.once("render").then(done));
    const errors = [];
    map.on("error", (e) => errors.push(e.error.message));
    map.addLayer({ id: "bad", type: "custom" });
    map.addLayer({ id: "probe", type: "custom", renderingMode: "3d", render(gl) { window.__depth = gl.isEnabled(gl.DEPTH_TEST); } });
    map.moveLayer("box");
    await map.once("idle");
    await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
    return {
      added: box.calls.added, gotMap: box.gotMap, prerender: box.calls.prerender > 0, repainted: box.calls.render > before, depth2d: box.depth, depth3d: window.__depth,
      options: { mvp: o.modelViewProjectionMatrix instanceof Float64Array && o.modelViewProjectionMatrix.length === 16, centre: [c[0] / c[2], c[1] / c[2]], fov: o.fov, near: o.nearZ, far: o.farZ, variant: o.shaderData.variantName },
      tile: o.getProjectionData({ tileID: { canonical: { x: 0, y: 0, z: 0 } } }).tileMercatorCoords,
      order: map.getLayersOrder(), style: map.getStyle().layers.map((l) => l.id), layer: map.getLayer("box") === box, errors,
    };
  });
  const over = await look();
  const removed = await page.evaluate(async () => {
    const map = window.__map;
    map.removeLayer("box");
    await map.once("idle");
    return { removed: window.__box.calls.removed, order: map.getLayersOrder() };
  });
  await frame();
  const gone = await look();

  const ok =
    near(under.box, blue) && near(under.both, red) && near(under.square, red) && near(under.out, white) &&
    near(over.both, blue) && near(over.square, red) && near(gone.box, white) && near(gone.both, red) &&
    r.added === 1 && r.gotMap && r.prerender && r.repainted && r.depth2d === false && r.depth3d === true &&
    r.options.mvp && Math.abs(r.options.centre[0]) < 1e-6 && Math.abs(r.options.centre[1]) < 1e-6 &&
    Math.abs(r.options.fov - 0.6435011087932844) < 1e-12 && r.options.near > 0 && r.options.far > r.options.near && r.options.variant === "mercator" &&
    JSON.stringify(r.tile) === JSON.stringify([0, 0, 1 / 8192, 1 / 8192]) &&
    JSON.stringify(r.order) === JSON.stringify(["background", "square", "probe", "box"]) &&
    JSON.stringify(r.style) === JSON.stringify(["background", "square"]) && r.layer &&
    r.errors.some((e) => /missing required method "render"/.test(e)) &&
    removed.removed === 1 && JSON.stringify(removed.order) === JSON.stringify(["background", "square", "probe"]);
  return [ok, { under, over, gone, ...r, removed }];
}
