import assert from "node:assert/strict";
import test from "node:test";
import * as edit from "../src/style.ts";
import type { StyleSpecification } from "../src/style.ts";

function style(): StyleSpecification {
  return {
    version: 8,
    sources: { v: { type: "vector", tiles: ["https://x/{z}/{x}/{y}.pbf"] }, g: { type: "geojson", data: { type: "FeatureCollection", features: [] } } },
    layers: [
      { id: "bg", type: "background" },
      { id: "a", type: "fill", source: "v", "source-layer": "a", paint: { "fill-color": "#f00" } },
      { id: "b", type: "line", source: "v", "source-layer": "b", filter: ["==", "k", 1] },
    ],
  };
}

const ids = (s: StyleSpecification) => (s.layers as { id: string }[]).map((l) => l.id);

test("addLayer, removeLayer and moveLayer keep the order MapLibre gives, and leave the input alone", () => {
  const s = style();
  const added = edit.addLayer(s, { id: "c", type: "circle", source: "g" }, "a");
  assert.deepEqual(ids(added), ["bg", "c", "a", "b"]);
  assert.deepEqual(ids(s), ["bg", "a", "b"]);
  assert.deepEqual(ids(edit.addLayer(s, { id: "c", type: "circle", source: "g" })), ["bg", "a", "b", "c"]);
  assert.deepEqual(ids(edit.removeLayer(s, "a")), ["bg", "b"]);
  assert.deepEqual(ids(edit.moveLayer(s, "b", "a")), ["bg", "b", "a"]);
  assert.deepEqual(ids(edit.moveLayer(s, "bg")), ["a", "b", "bg"]);
  assert.throws(() => edit.addLayer(s, { id: "a", type: "fill", source: "v" }), /already has a layer "a"/);
  assert.throws(() => edit.addLayer(s, { id: "c", type: "fill", source: "nope" }), /no source "nope"/);
  assert.throws(() => edit.addLayer(s, { id: "c", type: "fill", source: "v" }, "nope"), /no layer "nope"/);
  assert.throws(() => edit.removeLayer(s, "nope"), /no layer "nope"/);
  assert.throws(() => edit.moveLayer(s, "a", "nope"), /no layer "nope"/);
});

test("paint, layout, filter and zoom range edits touch one layer", () => {
  const s = style();
  const painted = edit.setPaintProperty(s, "a", "fill-opacity", 0.5);
  assert.deepEqual(edit.getLayer(painted, "a")?.paint, { "fill-color": "#f00", "fill-opacity": 0.5 });
  assert.equal(edit.getPaintProperty(s, "a", "fill-opacity"), undefined);
  assert.deepEqual(edit.getLayer(edit.setPaintProperty(painted, "a", "fill-color", null), "a")?.paint, { "fill-opacity": 0.5 });
  const hidden = edit.setLayoutProperty(s, "b", "visibility", "none");
  assert.equal(edit.getLayoutProperty(hidden, "b", "visibility"), "none");
  assert.equal(edit.getLayer(hidden, "a"), edit.getLayer(s, "a"));
  assert.deepEqual(edit.getFilter(edit.setFilter(s, "a", ["has", "k"]), "a"), ["has", "k"]);
  assert.equal("filter" in (edit.getLayer(edit.setFilter(s, "b", null), "b") ?? {}), false);
  const ranged = edit.getLayer(edit.setLayerZoomRange(s, "a", 10, 16), "a");
  assert.deepEqual([ranged?.minzoom, ranged?.maxzoom], [10, 16]);
  assert.throws(() => edit.setLayerZoomRange(s, "a", 16, 10), RangeError);
  assert.throws(() => edit.setPaintProperty(s, "nope", "fill-color", "#000"), /no layer "nope"/);
});

test("sources are added, refused while used, and GeoJSON data replaced", () => {
  const s = style();
  const added = edit.addSource(s, "d", { type: "raster-dem", tiles: ["https://x/{z}/{x}/{y}.png"] });
  assert.deepEqual(Object.keys(added.sources), ["v", "g", "d"]);
  assert.throws(() => edit.addSource(s, "v", { type: "vector" }), /already has a source "v"/);
  assert.throws(() => edit.addSource(s, "e", {}), /needs a type/);
  assert.deepEqual(Object.keys(edit.removeSource(s, "g").sources), ["v"]);
  assert.throws(() => edit.removeSource(s, "v"), /used by layer "a"/);
  assert.throws(() => edit.removeSource(edit.setRoot(added, "terrain", { source: "d" }), "d"), /used by the terrain/);
  assert.throws(() => edit.removeSource(s, "nope"), /no source "nope"/);
  const data = { type: "FeatureCollection", features: [{ type: "Feature", geometry: { type: "Point", coordinates: [1, 2] }, properties: {} }] };
  assert.deepEqual((edit.setSourceData(s, "g", data).sources.g as { data: unknown }).data, data);
  assert.throws(() => edit.setSourceData(s, "v", data), /not a GeoJSON source/);
});

test("keepGeoJSONData keeps the old data object where the new style writes it alike", () => {
  const s = style();
  const same = edit.keepGeoJSONData(s, edit.copy(s));
  assert.equal((same.sources.g as { data: unknown }).data, (s.sources.g as { data: unknown }).data);
  const changed = edit.keepGeoJSONData(s, edit.setSourceData(s, "g", "https://x/data.json"));
  assert.equal((changed.sources.g as { data: unknown }).data, "https://x/data.json");
  assert.equal(edit.keepGeoJSONData(null, s), s);
});

test("setRoot sets and removes terrain, sky and light", () => {
  const s = edit.setRoot(style(), "sky", { "sky-color": "#88c6fc" });
  assert.deepEqual(s.sky, { "sky-color": "#88c6fc" });
  assert.equal("sky" in edit.setRoot(s, "sky", null), false);
});

test("custom layers: placeholders need no source, getStyle leaves them out, MapLibre's validation", () => {
  const ids = (st: StyleSpecification) => st.layers.map((l) => (l as { id: string }).id);
  const s = edit.addLayer(style(), { id: "c", type: "custom" }, "a");
  assert.deepEqual(ids(s).slice(0, 3), ["bg", "c", "a"]);
  assert.deepEqual(ids(edit.withoutCustom(s)), ids(style()));
  assert.equal(edit.invalidCustomLayer({ id: "c", render() {} }), "");
  assert.equal(edit.invalidCustomLayer({ render() {} }), 'missing required property "id"');
  assert.equal(edit.invalidCustomLayer({ id: "c" }), 'missing required method "render"');
  assert.equal(edit.invalidCustomLayer({ id: "c", render() {}, renderingMode: "4d" }), 'property "renderingMode" must be either "2d" or "3d"');
});

test("styleWarnings pairs the engine's paths and messages and names each warning's layer", () => {
  const style = { version: 8, sources: {}, layers: [{ id: "a" }, { id: "b" }] } as unknown as StyleSpecification;
  assert.deepEqual(edit.styleWarnings(["layers[1].paint.line-blur", "not drawn yet", "sources.s.tiles", "only http(s) tile URLs", "layers[7]", "gone"], style), [
    { path: "layers[1].paint.line-blur", layer: "b", message: "not drawn yet" },
    { path: "sources.s.tiles", message: "only http(s) tile URLs" },
    { path: "layers[7]", message: "gone" },
  ]);
});

test("loadedState takes initial values over the style's defaults and keeps other keys", () => {
  const s = { ...style(), state: { a: { default: 1 }, b: {}, c: { default: [2] } } };
  assert.deepEqual(edit.loadedState({ a: 5, x: true }, s, { c: "init", d: 0 }), { a: 1, b: null, c: "init", d: 0, x: true });
  assert.deepEqual(edit.loadedState({}, style(), {}), {});
});

test("withState hands the engine the values as defaults, and leaves a style alone without any", () => {
  const s = { ...style(), state: { a: { default: 1 } } };
  assert.deepEqual(edit.withState(s, { a: 2, b: null }).state, { a: { default: 2 }, b: { default: null } });
  assert.equal(edit.withState(s, {}), s);
  assert.deepEqual(s.state, { a: { default: 1 } });
});
