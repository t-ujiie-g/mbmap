// A scale bar without its look: the bar's width and label, as MapLibre GL JS
// 6.16.0's ScaleControl computes them (BSD-3-Clause, Copyright (c) 2020 MapLibre
// contributors; see NOTICE).
import type { Map } from "../index";
import { Store, type Controller } from "./controller";
import { distanceTo, roundNumber } from "./measure";

export type ScaleUnit = "metric" | "imperial" | "nautical";

/** `width` in CSS pixels; `distance` a round number of `unit`; `label` as MapLibre writes it (a no-break space between). */
export interface ScaleState {
  width: number;
  distance: number;
  unit: "m" | "km" | "ft" | "mi" | "nm";
  label: string;
}

/** `maxWidth`: the longest the bar may be, in CSS pixels (default 100); `unit` (default `"metric"`). */
export interface ScaleOptions {
  maxWidth?: number;
  unit?: ScaleUnit;
}

export interface Scale extends Controller<ScaleState> {
  setUnit(unit: ScaleUnit): void;
}

/** The scale of `map` now, as MapLibre's `updateScale`. */
export function measureScale(map: Map, maxWidth = 100, unit: ScaleUnit = "metric"): ScaleState {
  const canvas = map.getCanvas();
  const [w, h] = [canvas.clientWidth, canvas.clientHeight];
  const left = map.unproject([w / 2 - maxWidth / 2, h / 2]);
  const right = map.unproject([w / 2 + maxWidth / 2, h / 2]);
  const globeWidth = Math.round(map.project(right).x - map.project(left).x);
  const width = Math.min(maxWidth, globeWidth, w);
  const meters = distanceTo(left, right);
  const [max, name]: [number, ScaleState["unit"]] =
    unit === "imperial"
      ? 3.2808 * meters > 5280
        ? [(3.2808 * meters) / 5280, "mi"]
        : [3.2808 * meters, "ft"]
      : unit === "nautical"
        ? [meters / 1852, "nm"]
        : meters >= 1000
          ? [meters / 1000, "km"]
          : [meters, "m"];
  const distance = roundNumber(max);
  return { width: width * (distance / max), distance, unit: name, label: `${distance} ${name}` };
}

class ScaleController extends Store<ScaleState> implements Scale {
  #map: Map;
  #maxWidth: number;
  #unit: ScaleUnit;

  constructor(map: Map, options: ScaleOptions) {
    const maxWidth = options.maxWidth ?? 100;
    const unit = options.unit ?? "metric";
    super(measureScale(map, maxWidth, unit));
    this.#map = map;
    this.#maxWidth = maxWidth;
    this.#unit = unit;
    this.listen(map, "move", () => this.#update());
    this.listen(map, "load", () => this.#update());
  }

  #update(): void {
    this.set(measureScale(this.#map, this.#maxWidth, this.#unit));
  }

  setUnit(unit: ScaleUnit): void {
    this.#unit = unit;
    this.#update();
  }
}

export function createScale(map: Map, options: ScaleOptions = {}): Scale {
  return new ScaleController(map, options);
}
