// Basemap switching without its look: a basemap's style swapped in with
// `setStyle`, the overlays of the current one kept (`withOverlays`).
import type { Map, StyleSpecification } from "../index";
import { Store, type Controller } from "./controller";
import { isOverlay, withOverlays } from "./overlays";

/** A basemap: its style, a URL of one, or a function making one when it is chosen. */
export interface Basemap {
  id: string;
  title?: string;
  style: StyleSpecification | string | (() => StyleSpecification | string);
}

export interface BasemapsState {
  active: string | null;
  basemaps: { id: string; title: string }[];
}

/**
 * `active`: the basemap drawn now (default none: the map's own style); `overlay(layer)`: the layers
 * to keep across basemaps (default those whose `metadata` says `"mbmap:overlay": true`).
 */
export interface BasemapsOptions {
  basemaps: Basemap[];
  active?: string;
  overlay?: (layer: { id: string; metadata?: unknown }) => boolean;
}

export interface Basemaps extends Controller<BasemapsState> {
  select(id: string): void;
}

class BasemapsStore extends Store<BasemapsState> implements Basemaps {
  #map: Map;
  #options: BasemapsOptions;

  constructor(map: Map, options: BasemapsOptions) {
    super({ active: options.active ?? null, basemaps: options.basemaps.map((b) => ({ id: b.id, title: b.title ?? b.id })) });
    this.#map = map;
    this.#options = options;
  }

  select(id: string): void {
    const basemap = this.#options.basemaps.find((b) => b.id === id);
    if (!basemap || id === this.state.active) return;
    const style = typeof basemap.style === "function" ? basemap.style() : basemap.style;
    const overlay = this.#options.overlay ?? isOverlay;
    this.#map.setStyle(style, { transformStyle: (previous, next) => withOverlays(previous, next, overlay) });
    this.set({ active: id });
  }
}

export function createBasemaps(map: Map, options: BasemapsOptions): Basemaps {
  return new BasemapsStore(map, options);
}
