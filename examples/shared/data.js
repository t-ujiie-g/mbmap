// Files read with mbmap/data and drawn as GeoJSON sources: CSV, Shapefile (zip), KML, GPX, TopoJSON,
// FlatGeobuf or GeoJSON. Each dataset stays in `datasets` (style.js), so that it survives a new style.
import { read, write } from "mbmap/data";
import { datasetLayers, datasetSource, datasets } from "./style.js";

export const WRITE_FORMATS = [["geojson", "GeoJSON", "application/geo+json"], ["csv", "CSV", "text/csv"], ["kml", "KML", "application/vnd.google-earth.kml+xml"]];

const SAMPLE = new URL("../shared/sample-parks.csv", location.href).href;

function boundsOf(geojson) {
  let box = null;
  const visit = (c) => {
    if (typeof c[0] !== "number") return c.forEach(visit);
    box = box ? [Math.min(box[0], c[0]), Math.min(box[1], c[1]), Math.max(box[2], c[0]), Math.max(box[3], c[1])] : [c[0], c[1], c[0], c[1]];
  };
  for (const f of geojson.features) if (f.geometry?.coordinates) visit(f.geometry.coordinates);
  return box;
}

/** A small store of the datasets on `map`: `state` is `{ items, loading, error }`, `subscribe` calls back on each change. */
export function createDataLoader(map) {
  const listeners = new Set();
  let serial = 0;
  const loader = {
    state: { items: [], loading: false, error: null },
    subscribe(f) {
      listeners.add(f);
      return () => listeners.delete(f);
    },
    /** Reads `input` (a URL or files) and puts it on the map, named `name`. */
    async add(input, name) {
      set({ loading: true, error: null });
      try {
        const table = await read(input);
        const data = table.toGeoJSON();
        const id = `data-${++serial}`;
        datasets.set(id, { name, data });
        map.addSource(id, datasetSource(data));
        for (const layer of datasetLayers(id)) map.addLayer(layer);
        const box = boundsOf(data);
        if (box) map.fitBounds([[box[0], box[1]], [box[2], box[3]]], { padding: 80, maxZoom: 15 });
        set({ loading: false, items: [...loader.state.items, { id, name, table, count: table.length, format: table.format }] });
      } catch (e) {
        set({ loading: false, error: `${name}：${e.message}` });
      }
    },
    addSample: () => loader.add(SAMPLE, "東京の公園（CSV）"),
    addFiles(files) {
      const list = [...files];
      if (list.length) return loader.add(list.length === 1 ? list[0] : list, list[0].name);
    },
    remove(id) {
      for (const layer of datasetLayers(id)) map.removeLayer(layer.id);
      map.removeSource(id);
      datasets.delete(id);
      set({ items: loader.state.items.filter((i) => i.id !== id) });
    },
    /** The dataset as text in `format`, saved as a file. */
    async save(item, format) {
      const [, , type] = WRITE_FORMATS.find(([f]) => f === format);
      const text = await write(item.table, { format });
      const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(new Blob([text], { type })), download: `${item.id}.${format}` });
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 1000);
      window.__written = { format, text };
    },
  };
  const set = (next) => {
    loader.state = { ...loader.state, ...next };
    for (const f of listeners) f(loader.state);
  };
  window.__data = loader;
  return loader;
}

const el = (tag, props = {}) => Object.assign(document.createElement(tag), props);

/** The loader drawn into `#data` with plain DOM. */
export function mountData(map) {
  const loader = createDataLoader(map);
  const box = document.getElementById("data");
  const drop = el("label", { className: "drop", textContent: "ファイルを選ぶか、ここへドロップ" });
  const input = el("input", { type: "file", multiple: true });
  input.addEventListener("change", () => void loader.addFiles(input.files));
  drop.append(input);
  drop.addEventListener("dragover", (e) => (e.preventDefault(), drop.classList.add("over")));
  drop.addEventListener("dragleave", () => drop.classList.remove("over"));
  drop.addEventListener("drop", (e) => {
    e.preventDefault();
    drop.classList.remove("over");
    void loader.addFiles(e.dataTransfer.files);
  });
  const sample = el("button", { textContent: "サンプルを読む" });
  sample.addEventListener("click", () => void loader.addSample());
  const actions = el("div", { className: "chips" });
  actions.style.marginTop = "6px";
  actions.append(sample);
  const hint = el("p", { className: "hint", textContent: "CSV、Shapefile（zip）、KML/KMZ、GPX、TopoJSON、FlatGeobuf、GeoJSON" });
  const error = el("p", { className: "data-error" });
  const list = el("ul", { className: "datasets" });
  box.append(drop, actions, hint, error, list);
  const draw = (s) => {
    sample.disabled = s.loading;
    error.hidden = !s.error;
    error.textContent = s.error ?? "";
    list.replaceChildren(
      ...s.items.map((item) => {
        const li = el("li");
        const buttons = el("div", { className: "chips" });
        for (const [format, label] of WRITE_FORMATS) {
          const b = el("button", { textContent: label });
          b.addEventListener("click", () => void loader.save(item, format));
          buttons.append(b);
        }
        const remove = el("button", { textContent: "消す" });
        remove.addEventListener("click", () => loader.remove(item.id));
        buttons.append(remove);
        li.append(el("b", { textContent: item.name }), el("small", { textContent: `  ${item.count} 件` }), buttons);
        return li;
      }),
    );
  };
  loader.subscribe(draw);
  draw(loader.state);
  return loader;
}
