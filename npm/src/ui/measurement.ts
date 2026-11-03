// Measuring a line or an area by clicks: lengths and area on the ellipsoid, the
// path drawn along the geodesics. The measuring is mbmap/geodesic's `measure`,
// passed by the page, so `mbmap/ui` loads no geodesic code itself.
import type { Map } from "../index";
import { Store, type Controller } from "./controller";
import { addOverlay } from "./overlays";

/** `[longitude, latitude]` in degrees. */
export type Position = [number, number];

/** What `mbmap/geodesic`'s `measure` is. */
export type Measure = (
  positions: Position[],
  options: { closed: boolean; step?: number },
) => Promise<{ length: number; area: number; distances: ArrayLike<number>; path?: Position[] }>;

/**
 * `mode` while measuring (null when not); `positions` placed; `pointer` the vertex that follows the
 * pointer until `finish`; `length` in meters (an area's perimeter) and `area` in square meters (null
 * for a line), both counting the pointer; `segments` each edge's length; `finished` once done.
 */
export interface MeasurementState {
  mode: "distance" | "area" | null;
  positions: Position[];
  pointer: Position | null;
  length: number;
  area: number | null;
  segments: number[];
  finished: boolean;
}

/**
 * `measure`: mbmap/geodesic's; `step`: meters between the points that draw each geodesic (default
 * 1000); `id`: of the GeoJSON source and the prefix of the layers drawn (default `"mbmap-measure"`);
 * `color`: of the line, the vertices and the area's fill (default `"#e4572e"`).
 */
export interface MeasurementOptions {
  measure: Measure;
  step?: number;
  id?: string;
  color?: string;
}

export interface Measurement extends Controller<MeasurementState> {
  start(mode: "distance" | "area"): void;
  add(position: Position): void;
  undo(): void;
  finish(): void;
  clear(): void;
}

const EMPTY = { type: "FeatureCollection", features: [] };

class MeasurementStore extends Store<MeasurementState> implements Measurement {
  #map: Map;
  #options: MeasurementOptions;
  #id: string;
  #dblclick: boolean | null = null;
  #unlayer: (() => void) | null = null;
  #dirty = false;
  #running = false;

  constructor(map: Map, options: MeasurementOptions) {
    super({ mode: null, positions: [], pointer: null, length: 0, area: null, segments: [], finished: false });
    this.#map = map;
    this.#options = options;
    this.#id = options.id ?? "mbmap-measure";
    this.listen(map, "click", (e) => {
      // The clicks of a double click land on the vertex already placed.
      const last = this.state.positions.at(-1);
      const p = last && map.project({ lng: last[0], lat: last[1] });
      if (!p || Math.hypot(p.x - e.point.x, p.y - e.point.y) > 3) this.add([e.lngLat.lng, e.lngLat.lat]);
    });
    this.listen(map, "mousemove", (e) => {
      if (this.#active()) this.#update({ pointer: [e.lngLat.lng, e.lngLat.lat] });
    });
    this.listen(map, "mouseout", () => {
      if (this.#active()) this.#update({ pointer: null });
    });
    this.listen(map, "dblclick", () => this.#active() && this.finish());
    this.onDestroy(() => this.#remove());
  }

  #active(): boolean {
    return this.state.mode !== null && !this.state.finished;
  }

  start(mode: "distance" | "area"): void {
    const map = this.#map;
    const id = this.#id;
    const color = this.#options.color ?? "#e4572e";
    this.#unlayer ??= addOverlay(map, [id], [
      { id: `${id}-fill`, type: "fill", source: id, filter: ["==", ["geometry-type"], "Polygon"], paint: { "fill-color": color, "fill-opacity": 0.15 } },
      { id: `${id}-line`, type: "line", source: id, filter: ["!=", ["geometry-type"], "Point"], paint: { "line-color": color, "line-width": 2.5 } },
      { id: `${id}-vertex`, type: "circle", source: id, filter: ["==", ["geometry-type"], "Point"], paint: { "circle-color": "#fff", "circle-radius": 4, "circle-stroke-color": color, "circle-stroke-width": 2 } },
    ]);
    this.#dblclick ??= map.doubleClickZoom.isEnabled();
    map.doubleClickZoom.disable();
    this.#update({ mode, positions: [], pointer: null, finished: false });
  }

  add(position: Position): void {
    if (this.#active()) this.#update({ positions: [...this.state.positions, position] });
  }

  undo(): void {
    if (this.state.mode) this.#update({ positions: this.state.positions.slice(0, -1), finished: false });
  }

  finish(): void {
    if (this.#active()) this.#update({ pointer: null, finished: true });
  }

  clear(): void {
    this.#restore();
    this.#update({ mode: null, positions: [], pointer: null, finished: false });
  }

  #restore(): void {
    if (this.#dblclick) this.#map.doubleClickZoom.enable();
    this.#dblclick = null;
  }

  #remove(): void {
    this.#restore();
    this.#unlayer?.();
    this.#unlayer = null;
  }

  /** Applies `patch` and measures again: one measure at a time, then once more for what came meanwhile. */
  async #update(patch: Partial<MeasurementState>): Promise<void> {
    this.set(patch);
    this.#dirty = true;
    if (this.#running) return;
    this.#running = true;
    while (this.#dirty) {
      this.#dirty = false;
      const { mode, positions, pointer } = this.state;
      const all = pointer ? [...positions, pointer] : positions;
      const closed = mode === "area";
      let m: Awaited<ReturnType<Measure>> = { length: 0, area: 0, distances: [], path: all };
      try {
        if (all.length > 1) m = await this.#options.measure(all, { closed, step: this.#options.step ?? 1000 });
      } catch {
        continue;
      }
      if (this.#dirty) continue;
      const d = Array.from(m.distances);
      const segments = d.slice(1).map((x, i) => x - d[i]);
      if (closed && all.length > 2) segments.push(m.length - d[d.length - 1]);
      this.set({ length: m.length, area: closed ? Math.abs(m.area) : null, segments });
      this.#draw(all, m.path ?? all, closed);
    }
    this.#running = false;
  }

  #draw(vertices: Position[], path: Position[], closed: boolean): void {
    const features: object[] = vertices.map((coordinates) => ({ type: "Feature", properties: {}, geometry: { type: "Point", coordinates } }));
    if (path.length > 1) {
      const geometry = closed && vertices.length > 2 ? { type: "Polygon", coordinates: [path] } : { type: "LineString", coordinates: path };
      features.push({ type: "Feature", properties: {}, geometry });
    }
    this.#map.getSource(this.#id)?.setData?.(this.state.mode ? { type: "FeatureCollection", features } : EMPTY);
  }
}

export function createMeasurement(map: Map, options: MeasurementOptions): Measurement {
  return new MeasurementStore(map, options);
}
