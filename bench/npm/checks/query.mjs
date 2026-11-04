// Queries and mouse events on a GeoJSON source added to the npm example's map (CI has no tile
// fixtures): points, layers, filters, source features, layer events and error paths.
export async function queryChecks(page) {
  const found = await page.evaluate(async () => {
    const map = window.__map;
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 15, bearing: 0, pitch: 0 });
    await map.once("idle");
    // A square west of the center, a line across it and a point on it.
    const [w, s] = [map.unproject([200, 400]), map.unproject([300, 200])];
    const square = [[w.lng, w.lat], [s.lng, w.lat], [s.lng, s.lat], [w.lng, s.lat], [w.lng, w.lat]];
    const mid = map.unproject([250, 300]);
    const data = {
      type: "FeatureCollection",
      features: [
        { type: "Feature", properties: { kind: "area", n: 1 }, geometry: { type: "Polygon", coordinates: [square] } },
        { type: "Feature", properties: { kind: "road", n: 2 }, geometry: { type: "LineString", coordinates: [[w.lng, mid.lat], [s.lng, mid.lat]] } },
        { type: "Feature", properties: { kind: "spot", n: 3 }, geometry: { type: "Point", coordinates: [mid.lng, mid.lat] } },
      ],
    };
    const idle = map.once("idle");
    map.addSource("q", { type: "geojson", data });
    map.addLayer({ id: "q-area", type: "fill", source: "q", filter: ["==", ["get", "kind"], "area"] });
    map.addLayer({ id: "q-road", type: "line", source: "q", filter: ["==", ["get", "kind"], "road"], paint: { "line-width": 6 } });
    map.addLayer({ id: "q-spot", type: "circle", source: "q", filter: ["==", ["get", "kind"], "spot"], paint: { "circle-radius": 8 } });
    await idle;
    const ids = (fs) => fs.map((f) => f.layer.id);
    const atSpot = await map.queryRenderedFeatures([250, 300], { layers: ["q-area", "q-road", "q-spot"] });
    const inArea = await map.queryRenderedFeatures([220, 380], { layers: ["q-area", "q-road", "q-spot"] });
    const outside = await map.queryRenderedFeatures([600, 300], { layers: ["q-area", "q-road", "q-spot"] });
    const box = await map.queryRenderedFeatures([[190, 190], [310, 410]], { filter: [">=", ["get", "n"], 2] });
    const errors = [];
    const f = (e) => errors.push(e.error.message);
    map.on("error", f);
    const unknown = await map.queryRenderedFeatures({ layers: ["nope"] });
    map.off("error", f);
    let refused = "";
    await map.queryRenderedFeatures({ filter: ["properties"] }).catch((e) => (refused = e.message));
    const source = await map.querySourceFeatures("q");
    window.__events = [];
    map.on("click", (e) => window.__events.push(["click", Math.round(e.point.x), Math.round(e.point.y), e.lngLat.lng > 139]));
    map.on("click", "q-area", (e) => window.__events.push(["click-area", e.features[0].layer.id, e.features[0].properties.n]));
    map.on("mouseenter", "q-area", () => window.__events.push(["enter"]));
    map.on("mouseleave", "q-area", () => window.__events.push(["leave"]));
    const r = map.getCanvas().getBoundingClientRect();
    return {
      origin: [r.left, r.top],
      atSpot: ids(atSpot), spot: atSpot[0] && { source: atSpot[0].source, state: atSpot[0].state, geometry: atSpot[0].geometry.type, n: atSpot[0].properties.n },
      inArea: ids(inArea), outside: outside.length, box: ids(box).filter((id) => id.startsWith("q-")),
      errors, unknown: unknown.length, refused,
      source: source.map((x) => x.properties.n).sort(),
    };
  });
  const [x, y] = [found.origin[0] + 220, found.origin[1] + 380];
  await page.mouse.move(found.origin[0] + 600, found.origin[1] + 500);
  await page.mouse.move(x, y, { steps: 4 });
  await page.waitForTimeout(300);
  await page.mouse.click(x, y);
  // A drag is not a click.
  await page.mouse.down();
  await page.mouse.move(x + 30, y, { steps: 3 });
  await page.mouse.up();
  await page.mouse.move(found.origin[0] + 600, found.origin[1] + 500, { steps: 2 });
  await page.waitForTimeout(300);
  const events = await page.evaluate(async () => {
    const map = window.__map;
    for (const id of ["q-spot", "q-road", "q-area"]) map.removeLayer(id);
    map.removeSource("q");
    map.jumpTo({ center: [139.7671, 35.6812], zoom: 15 });
    return window.__events;
  });
  const clicks = events.filter((e) => e[0] === "click");
  const ok =
    JSON.stringify(found.atSpot) === JSON.stringify(["q-spot", "q-road", "q-area"]) &&
    found.spot?.source === "q" && JSON.stringify(found.spot.state) === "{}" && found.spot.geometry === "Point" && found.spot.n === 3 &&
    JSON.stringify(found.inArea) === JSON.stringify(["q-area"]) &&
    found.outside === 0 &&
    JSON.stringify(found.box) === JSON.stringify(["q-spot", "q-road"]) &&
    found.unknown === 0 && /'nope' does not exist/.test(found.errors[0] ?? "") &&
    /unsupported: expression properties/.test(found.refused) &&
    // The square spans two tiles, and each gives its part, as MapLibre's do.
    JSON.stringify([...new Set(found.source)]) === JSON.stringify([1, 2, 3]) &&
    clicks.length === 1 && clicks[0][1] === 220 && clicks[0][2] === 380 && clicks[0][3] &&
    events.some((e) => e[0] === "click-area" && e[1] === "q-area" && e[2] === 1) &&
    events.filter((e) => e[0] === "enter").length >= 1 &&
    events.at(-1)[0] === "leave";
  return { ok, ...found, events };
}
