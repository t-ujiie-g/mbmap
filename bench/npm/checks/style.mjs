// The style API on the npm example's map: paint changes, hiding, moving and
// removing layers keep the tiles, showing a layer again loads them, setStyle swaps everything,
// GeoJSON sources come and go, and refused changes fire `error` and keep the style.
import { near, pixel } from "./pixels.mjs";
import { step } from "./step.mjs";

export async function styleChecks(page, requests) {
  const tiles = () => requests.filter((u) => u.endsWith(".pbf")).length;
  await step(page, "style: jumpTo", "map.jumpTo({ center: [139.7671, 35.6812], zoom: 14.5, bearing: 0, pitch: 0 });");
  const before = tiles();
  const original = await step(page, "style: setPaintProperty", 'const s = map.getStyle(); map.setPaintProperty("waterarea", "fill-color", "#00ff00"); map.setPaintProperty("background", "background-color", "#ff0000"); return s;');
  const painted = tiles();
  await step(page, "style: hide, move, remove", 'map.setLayoutProperty("waterarea", "visibility", "none"); map.moveLayer("road", "waterarea"); map.removeLayer("railway");');
  const kept = tiles();
  await step(page, "style: show again", 'map.setLayoutProperty("waterarea", "visibility", "visible");');
  const relaid = tiles();
  const errors = await page.evaluate(() => {
    const map = window.__map;
    const out = [];
    const f = (e) => out.push(e.error.message);
    map.on("error", f);
    map.setPaintProperty("nope", "fill-color", "#000");
    map.removeSource("gsi");
    map.setPaintProperty("road", "line-width", ["number-format", 2, {}]);
    map.off("error", f);
    return { out, width: map.getPaintProperty("road", "line-width"), order: map.getLayersOrder().slice(0, 4) };
  });
  await step(page, "style: setStyle", 'map.setStyle({ version: 8, sources: {}, layers: [{ id: "bg", type: "background", paint: { "background-color": "#ff0000" } }] });');
  const red = await pixel(page, 400, 300);
  const swapped = tiles();
  const point = (lng, lat) => ({ type: "FeatureCollection", features: [{ type: "Feature", properties: {}, geometry: { type: "Point", coordinates: [lng, lat] } }] });
  await step(page, "style: addSource", `map.addSource("pts", { type: "geojson", data: ${JSON.stringify(point(139.7671, 35.6812))} }); map.addLayer({ id: "pts", type: "circle", source: "pts", paint: { "circle-radius": 30, "circle-color": "#0000ff" } });`);
  const blue = await pixel(page, 400, 300);
  await step(page, "style: setData", `map.getSource("pts").setData(${JSON.stringify(point(139.8, 35.7))});`);
  const moved = await pixel(page, 400, 300);
  const order = await step(page, "style: removeSource", 'map.removeLayer("pts"); map.removeSource("pts"); return [map.getLayersOrder(), Object.keys(map.getStyle().sources)];');
  await step(page, "style: setStyle back", `map.setStyle(${JSON.stringify(original)});`);
  const restored = { tiles: tiles(), center: await pixel(page, 400, 300), layers: await page.evaluate(() => window.__map.getLayersOrder().length) };
  const ok =
    painted === before &&
    kept === painted &&
    relaid > kept &&
    errors.out.length === 3 &&
    /no layer "nope"/.test(errors.out[0]) &&
    /used by layer "road"/.test(errors.out[1]) &&
    /unsupported: expression number-format/.test(errors.out[2]) &&
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
