// Identifying features without a popup's look: the features drawn around a
// clicked point, one of them selected and highlighted through feature state.
import type { LngLat, Map, MapGeoJSONFeature } from "../index";
import { Store, type Controller } from "./controller";

/**
 * `point` and `lngLat` of the last identify (null before any or after `clear`); `features` there, top
 * first; `index` the selected one (-1 for none); `loading` while the query runs.
 */
export interface IdentifyState {
  point: { x: number; y: number } | null;
  lngLat: LngLat | null;
  features: MapGeoJSONFeature[];
  index: number;
  loading: boolean;
}

/**
 * `layers`: the layers to identify (default all); `radius`: CSS pixels around the point (default 3);
 * `highlight`: the feature-state key set on the selected feature (default `"selected"`, false for
 * none; the layers' paint reads it); `click`: identify on each click (default true).
 */
export interface IdentifyOptions {
  layers?: string[];
  radius?: number;
  highlight?: string | false;
  click?: boolean;
}

export interface Identify extends Controller<IdentifyState> {
  identify(point: { x: number; y: number }): Promise<void>;
  select(index: number): void;
  next(): void;
  previous(): void;
  clear(): void;
}

class IdentifyStore extends Store<IdentifyState> implements Identify {
  #map: Map;
  #options: IdentifyOptions;
  #ticket = 0;

  constructor(map: Map, options: IdentifyOptions) {
    super({ point: null, lngLat: null, features: [], index: -1, loading: false });
    this.#map = map;
    this.#options = options;
    if (options.click !== false) this.listen(map, "click", (e) => void this.identify(e.point));
    this.onDestroy(() => this.#highlight(-1));
  }

  async identify(point: { x: number; y: number }): Promise<void> {
    const ticket = ++this.#ticket;
    const r = this.#options.radius ?? 3;
    this.set({ loading: true });
    const features = await this.#map.queryRenderedFeatures(
      [
        [point.x - r, point.y - r],
        [point.x + r, point.y + r],
      ],
      this.#options.layers ? { layers: this.#options.layers } : {},
    );
    // A later identify, or a clear, has replaced this one.
    if (ticket !== this.#ticket) return;
    this.#highlight(-1);
    this.set({ point, lngLat: this.#map.unproject(point), features, index: -1, loading: false });
    this.select(features.length > 0 ? 0 : -1);
  }

  select(index: number): void {
    const n = this.state.features.length;
    const i = n === 0 ? -1 : Math.max(-1, Math.min(n - 1, index));
    this.#highlight(i);
    this.set({ index: i });
  }

  next(): void {
    const n = this.state.features.length;
    if (n > 0) this.select((this.state.index + 1) % n);
  }

  previous(): void {
    const n = this.state.features.length;
    if (n > 0) this.select((this.state.index - 1 + n) % n);
  }

  clear(): void {
    this.#ticket++;
    this.#highlight(-1);
    this.set({ point: null, lngLat: null, features: [], index: -1, loading: false });
  }

  /** Moves the highlight from the selected feature to feature `next` (-1: none). */
  #highlight(next: number): void {
    const key = this.#options.highlight ?? "selected";
    if (key === false) return;
    const set = (i: number, on: boolean) => {
      const f = this.state.features[i];
      if (!f || f.id === undefined) return;
      this.#map.setFeatureState({ source: f.source, sourceLayer: f.sourceLayer, id: f.id }, { [key]: on });
    };
    set(this.state.index, false);
    set(next, true);
  }
}

export function createIdentify(map: Map, options: IdentifyOptions = {}): Identify {
  return new IdentifyStore(map, options);
}
