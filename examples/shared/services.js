// GIS Web services read with mbmap/services and drawn over the map: the layers of a WMS or WMTS (another CRS's
// reprojected), an ArcGIS MapServer, ImageServer or VectorTileServer, and an ArcGIS layer's features.
import { allLayers, arcgisFeatures, arcgisService, arcgisSource, getCapabilities, wmsSource, wmtsSource } from "mbmap/services";
import { datasetLayers, datasetSource, datasets, firstVectorOverlay, serviceLayer, serviceLayers, tileUrl } from "./style.js";

const SAMPLE = new URL("../shared/services/gsi-wmts.xml", location.href).href;
const ARCGIS = /\/(MapServer|ImageServer|VectorTileServer|FeatureServer)(\/\d+)?\/?$/i;

/** What a service URL is: an ArcGIS service or layer, a WMTS (a URL naming WMTS), or else a WMS. */
export function serviceKind(url) {
  const path = url.replace(/[?#].*$/, "");
  if (ARCGIS.test(path)) return /\/\d+\/?$/.test(path) ? "arcgis-layer" : "arcgis";
  return /wmts/i.test(url) ? "wmts" : "wms";
}

/** A small store of a service's layers and the overlays added: `state` is `{ title, choices, items, loading, error }`. */
export function createServiceLoader(map) {
  const listeners = new Set();
  let serial = 0;
  let open = null;
  const loader = {
    state: { title: null, choices: [], items: [], loading: false, error: null },
    subscribe(f) {
      listeners.add(f);
      return () => listeners.delete(f);
    },
    /** Reads the service at `url` and lists what it can add. */
    async open(url) {
      set({ loading: true, error: null, choices: [], title: null });
      try {
        const kind = serviceKind(url);
        if (kind === "arcgis" || kind === "arcgis-layer") {
          const service = await arcgisService(url);
          const name = service.name ?? service.documentInfo?.Title ?? url.split("/").slice(-2).join("/");
          open = { kind, url, service };
          set({ loading: false, title: name, choices: [{ id: url, title: name }] });
          return;
        }
        const caps = await getCapabilities(url, kind === "wmts" ? "WMTS" : "WMS");
        open = { kind, url, caps };
        const choices = kind === "wmts" ? caps.layers.map((l) => ({ id: l.id, title: l.title || l.id })) : allLayers(caps.layers).filter((l) => l.name).map((l) => ({ id: l.name, title: l.title || l.name }));
        set({ loading: false, title: caps.title || url, choices });
      } catch (e) {
        set({ loading: false, error: e.message });
      }
    },
    openSample: () => loader.open(SAMPLE),
    /** Adds the open service's layer `choice` over the map. */
    async add(choice) {
      if (!open) return;
      set({ loading: true, error: null });
      try {
        const id = `service-${++serial}`;
        if (open.kind === "arcgis-layer") {
          const data = await arcgisFeatures(open.url, { maxFeatures: 5000 });
          datasets.set(id, { name: choice.title, data });
          map.addSource(id, datasetSource(data));
          for (const layer of datasetLayers(id)) map.addLayer(layer);
        } else {
          const made = open.kind === "arcgis" ? arcgisSource(open.service, open.url) : open.kind === "wmts" ? wmtsSource(open.caps, { layer: choice.id }) : wmsSource(open.caps, { layers: choice.id });
          if (made.type === "vector") throw new Error("ベクトルタイルのサービスはスタイルごと読む（arcgisStyle）");
          const source = made.tiles ? { ...made, tiles: made.tiles.map(tileUrl) } : made;
          serviceLayers.set(id, { name: choice.title, source });
          map.addSource(id, source);
          map.addLayer(serviceLayer(id), firstVectorOverlay(map.getStyle().layers));
        }
        set({ loading: false, items: [...loader.state.items, { id, name: choice.title }] });
      } catch (e) {
        set({ loading: false, error: e.message });
      }
    },
    remove(id) {
      const layers = datasets.has(id) ? datasetLayers(id).map((l) => l.id) : [id];
      for (const layer of layers) map.removeLayer(layer);
      map.removeSource(id);
      datasets.delete(id);
      serviceLayers.delete(id);
      set({ items: loader.state.items.filter((i) => i.id !== id) });
    },
  };
  const set = (next) => {
    loader.state = { ...loader.state, ...next };
    for (const f of listeners) f(loader.state);
  };
  window.__services = loader;
  return loader;
}

const el = (tag, props = {}) => Object.assign(document.createElement(tag), props);

/** The loader drawn into `#services` with plain DOM. */
export function mountServices(map) {
  const loader = createServiceLoader(map);
  const box = document.getElementById("services");
  const form = el("form", { className: "service-form" });
  const url = el("input", { type: "url", placeholder: "WMS・WMTS・ArcGIS の URL" });
  url.setAttribute("aria-label", "サービスの URL");
  form.append(url, el("button", { textContent: "読む" }));
  form.addEventListener("submit", (e) => {
    e.preventDefault();
    if (url.value) void loader.open(url.value);
  });
  const sample = el("button", { textContent: "地理院タイル（WMTS）を読む" });
  sample.addEventListener("click", () => void loader.openSample());
  const actions = el("div", { className: "chips" });
  actions.append(sample);
  const title = el("p", { className: "hint" });
  const choices = el("div", { className: "chips service-layers" });
  const error = el("p", { className: "data-error" });
  const list = el("ul", { className: "datasets" });
  box.append(form, actions, title, choices, error, list);
  const draw = (s) => {
    sample.disabled = s.loading;
    title.textContent = s.title ? `${s.title}：重ねるレイヤーを選ぶ` : "";
    choices.replaceChildren(
      ...s.choices.map((c) => {
        const b = el("button", { textContent: c.title });
        b.addEventListener("click", () => void loader.add(c));
        return b;
      }),
    );
    error.hidden = !s.error;
    error.textContent = s.error ?? "";
    list.replaceChildren(
      ...s.items.map((item) => {
        const li = el("li");
        const remove = el("button", { textContent: "消す" });
        remove.addEventListener("click", () => loader.remove(item.id));
        const buttons = el("div", { className: "chips" });
        buttons.append(remove);
        li.append(el("b", { textContent: item.name }), buttons);
        return li;
      }),
    );
  };
  loader.subscribe(draw);
  draw(loader.state);
  return loader;
}
