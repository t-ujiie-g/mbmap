// A layer list without its look: layers, or groups of them, to show and hide.
import type { LayerSpecification, Map } from "../index";
import { Store, type Controller } from "./controller";
import { inZoomRange } from "../attribution";

/**
 * One item, top first: its `layers` (those the style has), `visible` when all are shown, `mixed`
 * when some are, `inRange` when this zoom is in one's zoom range (shown or not).
 */
export interface LayerListItem {
  id: string;
  title: string;
  layers: string[];
  visible: boolean;
  mixed: boolean;
  inRange: boolean;
}

export interface LayerListState {
  items: LayerListItem[];
}

/**
 * `groups`: items made of several layers (`id`, `title`, `layers`), in the order given; without
 * them every layer but the background is an item; `title(layer)` as the legend's.
 */
export interface LayerListOptions {
  groups?: { id: string; title?: string; layers: string[] }[];
  title?: (layer: LayerSpecification) => string;
}

export interface LayerList extends Controller<LayerListState> {
  setVisible(id: string, visible: boolean): void;
  toggle(id: string): void;
}

class LayerListStore extends Store<LayerListState> implements LayerList {
  #map: Map;
  #options: LayerListOptions;
  #json = "";
  // The style's layers, read when the style changes: `getStyle` copies GeoJSON data too.
  #layers: LayerSpecification[] = [];

  constructor(map: Map, options: LayerListOptions) {
    super({ items: [] });
    this.#map = map;
    this.#options = options;
    const restyle = () => {
      this.#layers = (map.getStyle()?.layers ?? []) as LayerSpecification[];
      this.#update();
    };
    restyle();
    this.listen(map, "styledata", restyle);
    this.listen(map, "load", restyle);
    this.listen(map, "zoom", () => this.#update());
  }

  #update(): void {
    const layers = this.#layers;
    const zoom = this.#map.getZoom();
    const byId = new globalThis.Map(layers.map((l) => [l.id, l]));
    const groups =
      this.#options.groups ??
      [...layers]
        .reverse()
        .filter((l) => l.type !== "background")
        .map((l) => ({ id: l.id, title: this.#options.title?.(l), layers: [l.id] }));
    const items = groups.map((g) => {
      const layers = g.layers.filter((id) => byId.has(id));
      const shown = layers.filter((id) => (byId.get(id) as { layout?: { visibility?: string } }).layout?.visibility !== "none");
      const first = byId.get(layers[0]);
      return {
        id: g.id,
        title: g.title ?? (first ? (this.#options.title?.(first) ?? g.id) : g.id),
        layers,
        visible: layers.length > 0 && shown.length === layers.length,
        mixed: shown.length > 0 && shown.length < layers.length,
        inRange: layers.some((id) => inZoomRange(byId.get(id)!, zoom)),
      };
    });
    const json = JSON.stringify(items);
    if (json === this.#json) return;
    this.#json = json;
    this.set({ items });
  }

  setVisible(id: string, visible: boolean): void {
    const item = this.state.items.find((i) => i.id === id);
    for (const layer of item?.layers ?? []) this.#map.setLayoutProperty(layer, "visibility", visible ? "visible" : "none");
  }

  toggle(id: string): void {
    const item = this.state.items.find((i) => i.id === id);
    if (item) this.setVisible(id, !item.visible);
  }
}

export function createLayerList(map: Map, options: LayerListOptions = {}): LayerList {
  return new LayerListStore(map, options);
}
