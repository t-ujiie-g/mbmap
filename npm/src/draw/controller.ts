// Drawing on the map without a toolbar's look: the mode, the features drawn and
// the one being drawn, undo and redo. Shapes follow terra-draw's clicks (draw/shapes.ts);
// they are drawn through a GeoJSON source of the controller's own with setData.
import type { Map } from "../index";
import { Store, type Controller } from "../ui/controller";
import { CIRCLE_STEPS, CLOSE_PIXELS, FREEHAND_PIXELS, enoughVertices, finished, geometryOf, rectangleRing, type DrawMode, type Position } from "./shapes";

/** A feature drawn: `id` given by the controller, `properties.mode` the mode that drew it. */
export interface DrawnFeature {
  type: "Feature";
  id: string;
  properties: { mode: DrawMode; [key: string]: unknown };
  geometry: { type: string; coordinates: unknown };
}

/** What `mbmap/geodesic` gives for circles: `circle` and `inverse`. */
export interface Geodesic {
  circle(center: Position, radius: number, options?: { steps?: number }): Promise<Position[]>;
  inverse(from: Position, to: Position): Promise<{ distance: number }>;
}

/**
 * `mode` drawing (null for none); `features` drawn; `drawing` the shape under way (with the pointer)
 * or null; `vertices` placed for it; `canUndo` and `canRedo`.
 */
export interface DrawState {
  mode: DrawMode | null;
  features: DrawnFeature[];
  drawing: { type: string; coordinates: unknown } | null;
  vertices: Position[];
  canUndo: boolean;
  canRedo: boolean;
}

/**
 * `geodesic`: mbmap/geodesic (circle mode needs it); `id`: of the GeoJSON source and the prefix of the
 * layers (default `"mbmap-draw"`); `color` (default `"#3b6ed6"`); `steps`: points of a circle (default 64);
 * `precision`: decimals kept in the coordinates (default 9). Rings are kept counter-clockwise.
 */
export interface DrawOptions {
  geodesic?: Geodesic;
  id?: string;
  color?: string;
  steps?: number;
  precision?: number;
}

export interface Draw extends Controller<DrawState> {
  setMode(mode: DrawMode | null): void;
  finish(): void;
  cancel(): void;
  undo(): void;
  redo(): void;
  add(features: { geometry: { type: string; coordinates: unknown }; properties?: Record<string, unknown> }[]): void;
  remove(id: string): void;
  clear(): void;
}

const lngLat = (e: { lngLat: { lng: number; lat: number } }): Position => [e.lngLat.lng, e.lngLat.lat];

class DrawStore extends Store<DrawState> implements Draw {
  #map: Map;
  #options: DrawOptions;
  #id: string;
  #undone: DrawnFeature[][] = [];
  #done: DrawnFeature[][] = [];
  #next = 1;
  #pointer: Position | null = null;
  #ring: Position[] | null = null;
  #ticket = 0;
  #dblclick: boolean | null = null;

  constructor(map: Map, options: DrawOptions) {
    super({ mode: null, features: [], drawing: null, vertices: [], canUndo: false, canRedo: false });
    this.#map = map;
    this.#options = options;
    this.#id = options.id ?? "mbmap-draw";
    this.listen(map, "click", (e) => this.#click(lngLat(e), e.point));
    this.listen(map, "mousemove", (e) => this.#move(lngLat(e), e.point));
    this.onDestroy(() => this.#remove());
  }

  setMode(mode: DrawMode | null): void {
    if (mode === "circle" && !this.#options.geodesic) throw new Error("mbmap: draw: circles need the `geodesic` option (mbmap/geodesic)");
    this.#reset();
    if (mode) this.#layers();
    const map = this.#map;
    if (mode && this.#dblclick === null) {
      this.#dblclick = map.doubleClickZoom.isEnabled();
      map.doubleClickZoom.disable();
    } else if (!mode && this.#dblclick !== null) {
      if (this.#dblclick) map.doubleClickZoom.enable();
      this.#dblclick = null;
    }
    map.getCanvas().style.cursor = mode ? "crosshair" : "";
    this.#show({ mode });
  }

  /** Ends the shape under way: kept if it has enough vertices (Enter in terra-draw). */
  finish(): void {
    const { mode, vertices } = this.state;
    if (mode === "linestring" || mode === "polygon" || mode === "freehand") {
      if (enoughVertices(mode, vertices)) this.#commit(mode, geometryOf(mode, vertices)!);
      else this.#reset();
      this.#show({});
    }
  }

  /** Drops the shape under way (Escape in terra-draw). */
  cancel(): void {
    this.#reset();
    this.#show({});
  }

  /** While drawing, removes the last vertex; otherwise undoes the last change to the features. */
  undo(): void {
    const { mode, vertices } = this.state;
    if (vertices.length > 0) {
      const rest = mode === "rectangle" || mode === "circle" ? [] : vertices.slice(0, -1);
      if (rest.length === 0) this.#reset();
      this.#show({ vertices: rest });
      return;
    }
    const last = this.#done.pop();
    if (!last) return;
    this.#undone.push(this.state.features);
    this.#show({ features: last });
  }

  redo(): void {
    const next = this.#undone.pop();
    if (!next) return;
    this.#done.push(this.state.features);
    this.#show({ features: next });
  }

  add(features: { geometry: { type: string; coordinates: unknown }; properties?: Record<string, unknown> }[]): void {
    const made = features.map((f) => this.#feature({ ...f.properties, mode: (f.properties?.mode as DrawMode) ?? modeOf(f.geometry.type) }, f.geometry));
    this.#change([...this.state.features, ...made]);
  }

  remove(id: string): void {
    const features = this.state.features.filter((f) => f.id !== id);
    if (features.length !== this.state.features.length) this.#change(features);
  }

  clear(): void {
    if (this.state.features.length > 0) this.#change([]);
  }

  #feature(properties: DrawnFeature["properties"], geometry: DrawnFeature["geometry"]): DrawnFeature {
    return { type: "Feature", id: `d${this.#next++}`, properties, geometry };
  }

  #change(features: DrawnFeature[]): void {
    this.#done.push(this.state.features);
    this.#undone = [];
    this.#show({ features });
  }

  #commit(mode: DrawMode, geometry: DrawnFeature["geometry"]): void {
    const feature = this.#feature({ mode }, finished(geometry, this.#options.precision));
    this.#reset();
    this.#change([...this.state.features, feature]);
  }

  #reset(): void {
    this.#ticket++;
    this.#ring = null;
    if (this.state.vertices.length > 0) this.#show({ vertices: [] });
  }

  #near(a: Position | undefined, point: { x: number; y: number }, pixels: number): boolean {
    if (!a) return false;
    const p = this.#map.project({ lng: a[0], lat: a[1] });
    return Math.hypot(p.x - point.x, p.y - point.y) <= pixels;
  }

  #click(at: Position, point: { x: number; y: number }): void {
    const { mode, vertices } = this.state;
    if (!mode) return;
    this.#pointer = at;
    if (mode === "point") return this.#commit(mode, { type: "Point", coordinates: at });
    if (mode === "linestring" || mode === "polygon") {
      // A click on the last vertex finishes; for a polygon, so does one on the first.
      const closes = this.#near(vertices.at(-1), point, CLOSE_PIXELS) || (mode === "polygon" && vertices.length > 2 && this.#near(vertices[0], point, CLOSE_PIXELS));
      if (closes && vertices.length > 0) return this.finish();
      return this.#show({ vertices: [...vertices, at] });
    }
    if (mode === "freehand") return vertices.length === 0 ? this.#show({ vertices: [at] }) : this.finish();
    if (vertices.length === 0) return this.#show({ vertices: [at] });
    if (mode === "rectangle") return this.#commit(mode, { type: "Polygon", coordinates: [rectangleRing(vertices[0], at)] });
    void this.#circle(vertices[0], at, true);
  }

  #move(at: Position, point: { x: number; y: number }): void {
    const { mode, vertices } = this.state;
    if (!mode || vertices.length === 0) return;
    this.#pointer = at;
    if (mode === "freehand" && !this.#near(vertices.at(-1), point, FREEHAND_PIXELS)) return this.#show({ vertices: [...vertices, at] });
    if (mode === "circle") return void this.#circle(vertices[0], at, false);
    this.#show({});
  }

  /** The circle around `center` through `edge`, drawn (or kept, `commit`) when the geodesic worker answers. */
  async #circle(center: Position, edge: Position, commit: boolean): Promise<void> {
    const geodesic = this.#options.geodesic!;
    const ticket = ++this.#ticket;
    const { distance } = await geodesic.inverse(center, edge);
    const ring = await geodesic.circle(center, distance, { steps: this.#options.steps ?? CIRCLE_STEPS });
    if (ticket !== this.#ticket && !commit) return;
    if (commit) return this.#commit("circle", { type: "Polygon", coordinates: [ring] });
    this.#ring = ring;
    this.#show({});
  }

  /** Sets `patch`, then the shape under way with the pointer, and draws both. */
  #show(patch: Partial<DrawState>): void {
    this.set(patch);
    const { mode, vertices, features } = this.state;
    let drawing: DrawState["drawing"] = null;
    const p = this.#pointer;
    if (mode && vertices.length > 0) {
      if (mode === "rectangle") drawing = p ? { type: "Polygon", coordinates: [rectangleRing(vertices[0], p)] } : null;
      else if (mode === "circle") drawing = this.#ring ? { type: "Polygon", coordinates: [this.#ring] } : null;
      else drawing = geometryOf(mode, mode === "freehand" || !p ? vertices : [...vertices, p]);
    }
    this.set({ drawing, canUndo: this.#done.length > 0 || vertices.length > 0, canRedo: this.#undone.length > 0 });
    const shown: object[] = features.map((f) => ({ ...f, properties: { ...f.properties, kind: "feature" } }));
    if (drawing) shown.push({ type: "Feature", properties: { kind: "drawing" }, geometry: drawing });
    if (mode !== "freehand") for (const v of vertices) shown.push({ type: "Feature", properties: { kind: "vertex" }, geometry: { type: "Point", coordinates: v } });
    this.#map.getSource(this.#id)?.setData?.({ type: "FeatureCollection", features: shown });
  }

  #layers(): void {
    const map = this.#map;
    const id = this.#id;
    if (map.getSource(id)) return;
    const color = this.#options.color ?? "#3b6ed6";
    const metadata = { "mbmap:overlay": true };
    const kind = (k: string) => ["==", ["get", "kind"], k];
    const point = ["==", ["geometry-type"], "Point"];
    map.addSource(id, { type: "geojson", data: { type: "FeatureCollection", features: [] } });
    map.addLayer({ id: `${id}-fill`, type: "fill", source: id, filter: ["==", ["geometry-type"], "Polygon"], paint: { "fill-color": color, "fill-opacity": 0.2 }, metadata });
    map.addLayer({ id: `${id}-line`, type: "line", source: id, filter: ["!=", ["geometry-type"], "Point"], paint: { "line-color": color, "line-width": 2 }, metadata });
    map.addLayer({ id: `${id}-point`, type: "circle", source: id, filter: ["all", point, kind("feature")], paint: { "circle-color": color, "circle-radius": 6, "circle-stroke-color": "#fff", "circle-stroke-width": 2 }, metadata });
    map.addLayer({ id: `${id}-vertex`, type: "circle", source: id, filter: ["all", point, kind("vertex")], paint: { "circle-color": "#fff", "circle-radius": 4, "circle-stroke-color": color, "circle-stroke-width": 2 }, metadata });
  }

  #remove(): void {
    this.setMode(null);
    const map = this.#map;
    if (!map.getSource(this.#id)) return;
    for (const l of ["vertex", "point", "line", "fill"]) map.removeLayer(`${this.#id}-${l}`);
    map.removeSource(this.#id);
  }
}

function modeOf(type: string): DrawMode {
  return type === "Point" ? "point" : type === "LineString" ? "linestring" : "polygon";
}

export function createDraw(map: Map, options: DrawOptions = {}): Draw {
  return new DrawStore(map, options);
}
