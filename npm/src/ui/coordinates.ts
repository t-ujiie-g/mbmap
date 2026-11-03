// The coordinates of the pointer (or of the view's center) in several systems,
// without their look. Projected systems go through a `transform` the page
// passes (mbmap/analysis's), so `mbmap/ui` loads no projection code itself.
import type { LngLat, Map } from "../index";
import { Store, type Controller } from "./controller";
import { formatDegrees, formatDms, utmZone } from "./format";

/** One system: its `title` and how it writes a place (a Promise for a projected one). */
export interface CoordinateSystem {
  id: string;
  title: string;
  format(p: LngLat): string | Promise<string>;
}

/** `lngLat` of the pointer, or of the center when the pointer is off the map (`source`); `values` in each system. */
export interface CoordinatesState {
  lngLat: LngLat | null;
  source: "pointer" | "center";
  values: { id: string; title: string; text: string }[];
}

/** `systems` (default decimal degrees and degrees-minutes-seconds); `follow` the pointer (default) or only the center. */
export interface CoordinatesOptions {
  systems?: CoordinateSystem[];
  follow?: "pointer" | "center";
}

/** What `mbmap/analysis`'s `transform` is: coordinates from one CRS to another. */
export type Transform = (coords: ArrayLike<number>, from: number | string, to: number | string) => Promise<ArrayLike<number>>;

export function degrees(digits = 5): CoordinateSystem {
  return { id: "degrees", title: "Degrees", format: (p) => formatDegrees(p, digits) };
}

export function degreesMinutesSeconds(digits = 1): CoordinateSystem {
  return { id: "dms", title: "DMS", format: (p) => formatDms(p, digits) };
}

/**
 * A projected CRS through `transform`: `crs` names it, or a function picks it for a place (a zone);
 * the text is easting and northing in meters (`digits` decimals).
 */
export function projected(options: {
  id: string;
  title: string;
  transform: Transform;
  crs: number | string | ((p: LngLat) => number | string);
  digits?: number;
}): CoordinateSystem {
  const { transform, crs, digits = 1 } = options;
  return {
    id: options.id,
    title: options.title,
    async format(p) {
      const xy = await transform([p.lng, p.lat], 4326, typeof crs === "function" ? crs(p) : crs);
      // Japan's plane rectangular systems call northing X and easting Y.
      return `X ${xy[1].toFixed(digits)} m, Y ${xy[0].toFixed(digits)} m`;
    },
  };
}

/** WGS 84 UTM in the zone of the place, through `transform`: the zone, easting and northing. */
export function utm(transform: Transform, digits = 0): CoordinateSystem {
  return {
    id: "utm",
    title: "UTM",
    async format(p) {
      const z = utmZone(p);
      const en = await transform([p.lng, p.lat], 4326, z.epsg);
      return `${z.zone}${z.north ? "N" : "S"} ${en[0].toFixed(digits)} ${en[1].toFixed(digits)}`;
    },
  };
}

class CoordinatesStore extends Store<CoordinatesState> {
  #map: Map;
  #systems: CoordinateSystem[];
  #next: { lngLat: LngLat; source: "pointer" | "center" } | null = null;
  #running = false;

  constructor(map: Map, options: CoordinatesOptions) {
    super({ lngLat: null, source: "center", values: [] });
    this.#map = map;
    this.#systems = options.systems ?? [degrees(), degreesMinutesSeconds()];
    const center = () => {
      if (this.state.source === "center") void this.#show(map.getCenter(), "center");
    };
    this.listen(map, "move", center);
    this.listen(map, "load", center);
    if (options.follow !== "center") {
      this.listen(map, "mousemove", (e) => void this.#show(e.lngLat, "pointer"));
      this.listen(map, "mouseout", () => void this.#show(map.getCenter(), "center"));
    }
    void this.#show(map.getCenter(), "center");
  }

  /** Shows `lngLat`: one conversion at a time, and only the latest position asked for while it runs. */
  async #show(lngLat: LngLat, source: "pointer" | "center"): Promise<void> {
    if (!Number.isFinite(lngLat.lng) || !Number.isFinite(lngLat.lat)) return;
    this.#next = { lngLat, source };
    if (this.#running) return;
    this.#running = true;
    while (this.#next) {
      const at = this.#next;
      this.#next = null;
      const texts = await Promise.all(
        this.#systems.map(async (s) => {
          try {
            return await s.format(at.lngLat);
          } catch {
            return "";
          }
        }),
      );
      this.set({ ...at, values: this.#systems.map((s, i) => ({ id: s.id, title: s.title, text: texts[i] })) });
    }
    this.#running = false;
  }
}

export function createCoordinates(map: Map, options: CoordinatesOptions = {}): Controller<CoordinatesState> {
  return new CoordinatesStore(map, options);
}
