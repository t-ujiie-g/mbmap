// A legend without its look: each layer's swatches from its style, colors as
// drawn at the current zoom (the engine evaluates them).
import type { LayerSpecification, Map, PaintValues } from "../index";
import { layerShown } from "../attribution";
import { Store, type Controller } from "./controller";
import { breakdown, COLOR_PROPERTY, defaultLabel, type LegendCategory } from "./legend-rules";

/** One swatch: its label, what it stands for (`LegendCategory`) and its paint as drawn. */
export interface LegendItem {
  label: string;
  category: LegendCategory;
  paint: PaintValues;
}

/**
 * One layer, top first: `visible` when shown at this zoom; `kind` and `property` say how its color
 * splits (`single` for one swatch); raster and hillshade layers have no items.
 */
export interface LegendEntry {
  id: string;
  type: string;
  title: string;
  visible: boolean;
  kind: "single" | "match" | "step" | "interpolate";
  property: string | null;
  items: LegendItem[];
}

export interface LegendState {
  entries: LegendEntry[];
}

/**
 * `layers`: the layer ids to show (default all but the background); `title(layer)`: an entry's
 * title (default `metadata["mbmap:title"]`, else the id); `label(layer, category)`: an item's label.
 */
export interface LegendOptions {
  layers?: string[];
  title?: (layer: LayerSpecification) => string;
  label?: (layer: LayerSpecification, category: LegendCategory) => string | undefined;
}

function titleOf(layer: LayerSpecification): string {
  const t = (layer as { metadata?: Record<string, unknown> }).metadata?.["mbmap:title"];
  return typeof t === "string" ? t : layer.id;
}

class LegendStore extends Store<LegendState> {
  #map: Map;
  #options: LegendOptions;
  #json = "";
  // The style's layers, read when the style changes: `getStyle` copies GeoJSON data too.
  #layers: LayerSpecification[] = [];

  constructor(map: Map, options: LegendOptions) {
    super({ entries: [] });
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
    const wanted = this.#options.layers ? new Set(this.#options.layers) : null;
    const entries: LegendEntry[] = [];
    for (const layer of [...layers].reverse()) {
      if (wanted ? !wanted.has(layer.id) : layer.type === "background") continue;
      const colorProperty = COLOR_PROPERTY[layer.type];
      const color = colorProperty ? (layer as { paint?: Record<string, unknown> }).paint?.[colorProperty] : undefined;
      const b = breakdown(color);
      const items: LegendItem[] = [];
      if (colorProperty) {
        for (const category of b.categories) {
          const paint = this.#map.evaluatePaint(layer.id, category.properties);
          if (!paint) continue;
          items.push({ label: this.#options.label?.(layer, category) ?? defaultLabel(category), category, paint });
        }
      }
      entries.push({
        id: layer.id,
        type: layer.type,
        title: this.#options.title?.(layer) ?? titleOf(layer),
        visible: layerShown(layer, zoom),
        kind: b.kind,
        property: b.property,
        items,
      });
    }
    // Zoom events come every frame: tell listeners only of a different legend.
    const json = JSON.stringify(entries);
    if (json === this.#json) return;
    this.#json = json;
    this.set({ entries });
  }
}

export function createLegend(map: Map, options: LegendOptions = {}): Controller<LegendState> {
  return new LegendStore(map, options);
}
