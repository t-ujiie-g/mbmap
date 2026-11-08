// `updateData` on the GeoJSON test page: a diff changes what is queried, `getData` and `getStyle`, asks the GeoJSON
// worker only for tiles around what it touched (fewer than `setData`), waits behind a URL source's load, and is
// refused with MapLibre's error for data whose features lack ids.
export async function updateDataChecks(page) {
  const r = await page.evaluate(async () => {
    const map = window.__map;
    map.jumpTo({ center: [139.763, 35.681], zoom: 15, pitch: 0, bearing: 0 });
    // Tiles asked of the GeoJSON worker: its tile messages carry no bytes or URL.
    let asked = 0;
    const post = Worker.prototype.postMessage;
    Worker.prototype.postMessage = function (m, t) {
      if (m?.type === "tile" && !("bytes" in m) && !("url" in m)) asked++;
      return post.call(this, m, t);
    };
    const errors = [];
    map.on("error", (e) => errors.push(e.error.message));
    const point = (id, x, kind) => ({ type: "Feature", id, properties: { kind }, geometry: { type: "Point", coordinates: [x, 35.681] } });
    const data = { type: "FeatureCollection", features: [point(1, 139.763, "a"), point("two", 139.77, "a"), point(3, 139.756, "a")] };
    map.addSource("edits", { type: "geojson", data });
    map.addLayer({ id: "edits", type: "circle", source: "edits", paint: { "circle-radius": 8, "circle-color": ["match", ["get", "kind"], "b", "#ff0000", "#0000ff"] } });
    await map.once("idle");
    const kinds = async () => (await map.queryRenderedFeatures({ layers: ["edits"] })).map((f) => `${f.id}:${f.properties.kind}`).sort();
    const before = await kinds();
    const source = map.getSource("edits");
    asked = 0;
    // Two diffs at once: the second waits for the first's load and goes alone.
    const done = Promise.all([
      source.updateData({ update: [{ id: 1, addOrUpdateProperties: [{ key: "kind", value: "b" }] }] }),
      source.updateData({ add: [point(4, 139.7635, "b")] }),
    ]);
    const pending = (await source.getData()).features.length;
    await done;
    await map.once("idle");
    const updated = asked;
    const after = await kinds();
    const got = await source.getData();
    const styled = map.getStyle().sources.edits.data.features.length;
    asked = 0;
    source.setData(got);
    await map.once("idle");
    const all = asked;
    await map.getSource("route").updateData({ remove: [0] });
    map.addSource("named", { type: "geojson", data: "places.geojson", promoteId: "name" });
    const named = map.getSource("named");
    const names = (await named.getData()).features.map((f) => f.properties.name);
    await named.updateData({ remove: [names[0]] });
    const left = (await named.getData()).features.map((f) => f.properties.name);
    Worker.prototype.postMessage = post;
    return { before, after, pending, ids: got.features.map((f) => f.id), styled, updated, all, errors, names: names.length, left: left.length, first: left.includes(names[0]) };
  });
  const ok =
    JSON.stringify(r.before) === JSON.stringify(["1:a", "3:a", "two:a"]) &&
    JSON.stringify(r.after) === JSON.stringify(["1:b", "3:a", "4:b", "two:a"]) &&
    r.pending === 3 &&
    JSON.stringify(r.ids) === JSON.stringify([1, "two", 3, 4]) &&
    r.styled === 4 &&
    r.updated > 0 && r.updated < r.all &&
    JSON.stringify(r.errors) === JSON.stringify(['mbmap: GeoJSONSource "route": GeoJSON data is not compatible with updateData']) &&
    r.names === 8 && r.left === 7 && !r.first;
  return { ok, ...r };
}
