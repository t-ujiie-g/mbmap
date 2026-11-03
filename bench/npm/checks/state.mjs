// Feature state on the npm example's map: two squares, one by GeoJSON id and
// one by a promoted property, are drawn red while their state says `on`.
import { near, pixel } from "./pixels.mjs";
import { step } from "./step.mjs";

export async function stateChecks(page) {
  await step(page, "state: two squares", `
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
  const set = await step(page, "state: setFeatureState", `
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
  await step(page, "state: removeFeatureState", `map.removeFeatureState({ source: "pr", id: "b" }, "on"); map.removeFeatureState({ source: "st" });`);
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
