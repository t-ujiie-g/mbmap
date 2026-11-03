// Drawing and editing on the map without a toolbar's look: the mode, the features,
// the one being drawn or selected, undo and redo. Clicks, drags and snapping follow
// terra-draw's; shapes are drawn through a GeoJSON source of the controller's own.
import type { Map } from "../index";
import { Store, type Controller } from "../ui/controller";
import { deleteVertex, insertVertex, insideRing, midpoints, moveVertex, nearestOnSegment, translate, vertices as verticesOf, type At } from "./edit";
import { CIRCLE_STEPS, CLOSE_PIXELS, FREEHAND_PIXELS, enoughVertices, finished, geometryOf, rectangleRing, type DrawMode, type Position } from "./shapes";

/** The modes: drawing one of the shapes, `"select"` to pick and edit them, `"split"` to draw a line that cuts them. */
export type EditMode = DrawMode | "select" | "split";

/** A feature drawn: `id` given by the controller, `properties.mode` the mode that drew it. */
export interface DrawnFeature {
  type: "Feature";
  id: string;
  properties: { mode: DrawMode; [key: string]: unknown };
  geometry: { type: string; coordinates: unknown };
}

type Plain = { properties?: Record<string, unknown> | null; geometry: { type: string; coordinates: unknown } };

/** What `mbmap/analysis` gives for splitting and merging: `splitFeatures` and `mergeFeatures`. */
export interface GeometryOps {
  split(features: Plain[], line: { type: string; coordinates: unknown }): Promise<Plain[]>;
  merge(features: Plain[]): Promise<Plain>;
}

/** What `mbmap/geodesic` gives for circles: `circle` and `inverse`. */
export interface Geodesic {
  circle(center: Position, radius: number, options?: { steps?: number }): Promise<Position[]>;
  inverse(from: Position, to: Position): Promise<{ distance: number }>;
}

/**
 * `mode` (null for none); `features` drawn; `drawing` the shape under way (with the pointer) or null;
 * `vertices` placed for it; `selection` the ids picked in `"select"` mode (Shift adds), `selected` the
 * last of them; `canUndo` and `canRedo`.
 */
export interface DrawState {
  mode: EditMode | null;
  selected: string | null;
  selection: string[];
  features: DrawnFeature[];
  drawing: { type: string; coordinates: unknown } | null;
  vertices: Position[];
  canUndo: boolean;
  canRedo: boolean;
}

/**
 * `geodesic`: mbmap/geodesic (circle mode needs it); `id`: of the GeoJSON source and the prefix of the
 * layers (default `"mbmap-draw"`); `color` (default `"#3b6ed6"`); `steps`: points of a circle (default 64);
 * `geometry`: mbmap/analysis's `{ split: splitFeatures, merge: mergeFeatures }` (split and merge need it);
 * `precision`: decimals kept in the coordinates (default 9); `snapping`: to the other features'
 * `vertices` and `lines` within `pixels` (default 40, as terra-draw), `true` for both. Rings stay counter-clockwise.
 */
export interface DrawOptions {
  geometry?: GeometryOps;
  snapping?: boolean | { vertices?: boolean; lines?: boolean; pixels?: number };
  geodesic?: Geodesic;
  id?: string;
  color?: string;
  steps?: number;
  precision?: number;
}

export interface Draw extends Controller<DrawState> {
  setMode(mode: EditMode | null): void;
  select(id: string | null): void;
  setProperties(id: string, properties: Record<string, unknown>): void;
  deleteSelected(): void;
  merge(): Promise<void>;
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
  /** Whether double-click and box zoom were on before a mode turned them off (Shift+click selects). */
  #zooms: [boolean, boolean] | null = null;
  #drag: { at: At | null; from: Position; before: DrawnFeature[]; pan: boolean } | null = null;

  constructor(map: Map, options: DrawOptions) {
    super({ mode: null, selected: null, selection: [], features: [], drawing: null, vertices: [], canUndo: false, canRedo: false });
    this.#map = map;
    this.#options = options;
    this.#id = options.id ?? "mbmap-draw";
    this.listen(map, "click", (e) => this.#click(lngLat(e), e.point, e.originalEvent?.shiftKey));
    this.listen(map, "mousemove", (e) => this.#move(lngLat(e), e.point));
    this.listen(map, "mousedown", (e) => this.#press(lngLat(e), e.point));
    this.listen(map, "mouseup", () => this.#release());
    this.listen(map, "contextmenu", (e) => this.#unvertex(e.point));
    this.onDestroy(() => this.#remove());
  }

  setMode(mode: EditMode | null): void {
    if (mode === "circle" && !this.#options.geodesic) throw new Error("mbmap: draw: circles need the `geodesic` option (mbmap/geodesic)");
    if (mode === "split" && !this.#options.geometry) throw new Error("mbmap: draw: splitting needs the `geometry` option (mbmap/analysis)");
    this.#reset();
    if (mode) this.#layers();
    const map = this.#map;
    const handlers = [map.doubleClickZoom, map.boxZoom];
    if (mode && !this.#zooms) {
      this.#zooms = [handlers[0].isEnabled(), handlers[1].isEnabled()];
      for (const h of handlers) h.disable();
    } else if (!mode && this.#zooms) {
      this.#zooms.forEach((on, i) => on && handlers[i].enable());
      this.#zooms = null;
    }
    map.getCanvas().style.cursor = mode && mode !== "select" ? "crosshair" : "";
    // The selection stays for a split, which cuts it.
    this.#show(mode === "select" || mode === "split" ? { mode } : { mode, selected: null, selection: [] });
  }

  /** Selects feature `id` alone (null for none), or with `add` toggles it in the selection. */
  select(id: string | null, add = false): void {
    const known = this.state.features.some((f) => f.id === id) ? id : null;
    const was = this.state.selection;
    const selection = !known ? (add ? was : []) : !add ? [known] : was.includes(known) ? was.filter((x) => x !== known) : [...was, known];
    this.#show({ selection, selected: selection.at(-1) ?? null });
  }

  /** The selected features as one (mbmap/analysis's `merge`), replacing them; one step to undo. */
  async merge(): Promise<void> {
    const ids = this.state.selection;
    const geometry = this.#options.geometry;
    if (!geometry || ids.length < 2) return;
    const parts = ids.map((id) => this.state.features.find((f) => f.id === id)!);
    const merged = await geometry.merge(parts);
    const feature = this.#feature({ ...merged.properties, mode: modeOf(merged.geometry.type) }, finished(merged.geometry, this.#options.precision));
    const features = this.state.features.filter((f) => !ids.includes(f.id));
    this.#change([...features, feature]);
    this.select(feature.id);
  }

  /** The features (the selection, or all) cut by `line` (mbmap/analysis's `split`), each replaced by its pieces. */
  async #split(line: DrawnFeature["geometry"]): Promise<void> {
    const before = this.state.features;
    const ids = this.state.selection.length > 0 ? this.state.selection : before.map((f) => f.id);
    const targets = before.filter((f) => ids.includes(f.id));
    const pieces = await this.#options.geometry!.split(targets.map((f) => ({ properties: { ...f.properties, [SOURCE]: f.id }, geometry: f.geometry })), line);
    const features = before.flatMap((f) => {
      const mine = pieces.filter((p) => p.properties?.[SOURCE] === f.id);
      if (!ids.includes(f.id) || mine.length < 2) return [f];
      return mine.map((p) => {
        const { [SOURCE]: _, ...properties } = p.properties ?? {};
        return this.#feature({ ...properties, mode: f.properties.mode }, finished(p.geometry, this.#options.precision));
      });
    });
    if (features.length !== before.length) this.#change(features, before);
  }

  /** Merges `properties` into feature `id`'s (null removes a key); `mode` stays. */
  setProperties(id: string, properties: Record<string, unknown>): void {
    this.#change(this.state.features.map((f) => {
      if (f.id !== id) return f;
      const next: Record<string, unknown> = { ...f.properties, ...properties, mode: f.properties.mode };
      for (const [k, v] of Object.entries(properties)) if (v === null && k !== "mode") delete next[k];
      return { ...f, properties: next as DrawnFeature["properties"] };
    }));
  }

  deleteSelected(): void {
    const ids = this.state.selection;
    if (ids.length > 0) this.#change(this.state.features.filter((f) => !ids.includes(f.id)));
  }

  /** Ends the shape under way: kept if it has enough vertices (Enter in terra-draw). */
  finish(): void {
    const { mode, vertices } = this.state;
    if (mode === "split" && enoughVertices("linestring", vertices)) {
      const line = geometryOf("linestring", vertices)!;
      this.#reset();
      void this.#split(line);
    } else if (mode === "linestring" || mode === "polygon" || mode === "freehand") {
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
    this.#show({ features: last, ...kept(last, this.state.selection) });
  }

  redo(): void {
    const next = this.#undone.pop();
    if (!next) return;
    this.#done.push(this.state.features);
    this.#show({ features: next, ...kept(next, this.state.selection) });
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

  #change(features: DrawnFeature[], before = this.state.features): void {
    this.#done.push(before);
    this.#undone = [];
    this.#show({ features, ...kept(features, this.state.selection) });
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

  #click(at: Position, point: { x: number; y: number }, shift = false): void {
    const { mode, vertices } = this.state;
    if (!mode) return;
    if (mode === "select") return this.select(this.#hit(point)?.id ?? null, shift);
    if (mode !== "freehand") at = this.#snap(at, point, null);
    this.#pointer = at;
    if (mode === "point") return this.#commit(mode, { type: "Point", coordinates: at });
    if (mode === "linestring" || mode === "polygon" || mode === "split") {
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
    if (this.#drag) return this.#dragTo(at, point);
    const { mode, vertices } = this.state;
    if (!mode || mode === "select" || vertices.length === 0) return;
    if (mode !== "freehand") at = this.#snap(at, point, null);
    this.#pointer = at;
    if (mode === "freehand" && !this.#near(vertices.at(-1), point, FREEHAND_PIXELS)) return this.#show({ vertices: [...vertices, at] });
    if (mode === "circle") return void this.#circle(vertices[0], at, false);
    this.#show({});
  }

  /** The selected feature when it is the only one. */
  #selectedFeature(): DrawnFeature | undefined {
    return this.state.selection.length === 1 ? this.state.features.find((f) => f.id === this.state.selected) : undefined;
  }

  #screen(p: Position): { x: number; y: number } {
    return this.#map.project({ lng: p[0], lat: p[1] });
  }

  /** The topmost feature under `point`: a point or line within `CLOSE_PIXELS`, a polygon around it or near its edge. */
  #hit(point: { x: number; y: number }): DrawnFeature | undefined {
    const near = (q: { x: number; y: number }) => Math.hypot(q.x - point.x, q.y - point.y) <= CLOSE_PIXELS;
    return [...this.state.features].reverse().find((f) => {
      const g = f.geometry;
      const c = g.coordinates as any;
      if (g.type === "Point") return near(this.#screen(c));
      if (g.type === "MultiPoint") return c.some((p: Position) => near(this.#screen(p)));
      const rs: Position[][] = g.type === "LineString" ? [c] : g.type === "MultiPolygon" ? c.flat() : c;
      const area = g.type.endsWith("Polygon");
      return rs.some((r) => {
        const xy = r.map((p) => this.#screen(p));
        return (area && insideRing(point, xy)) || xy.slice(1).some((b, i) => near(nearestOnSegment(point, xy[i], b)));
      });
    });
  }

  /** `at` moved onto a vertex or edge of the features but `exclude` within the snapping distance. */
  #snap(at: Position, point: { x: number; y: number }, exclude: string | null): Position {
    const o = this.#options.snapping;
    if (!o) return at;
    const { vertices = true, lines = true, pixels = CLOSE_PIXELS } = o === true ? {} : o;
    let best = pixels;
    let snapped = at;
    const consider = (q: { x: number; y: number }, to: () => Position) => {
      const d = Math.hypot(q.x - point.x, q.y - point.y);
      if (d <= best) [best, snapped] = [d, to()];
    };
    const others = this.state.features.filter((f) => f.id !== exclude);
    if (vertices) for (const f of others) for (const v of verticesOf(f.geometry)) consider(this.#screen(v.position), () => v.position);
    if (snapped !== at || !lines) return snapped;
    for (const f of others) {
      if (f.geometry.type === "Point") continue;
      const rs = f.geometry.type === "LineString" ? [f.geometry.coordinates as Position[]] : (f.geometry.coordinates as Position[][]);
      for (const r of rs) {
        const xy = r.map((p) => this.#screen(p));
        for (let i = 1; i < xy.length; i++) {
          const q = nearestOnSegment(point, xy[i - 1], xy[i]);
          consider(q, () => {
            const ll = this.#map.unproject([q.x, q.y]);
            return [ll.lng, ll.lat];
          });
        }
      }
    }
    return snapped;
  }

  /** In `"select"` mode, a press on the selected feature's vertex, midpoint or body starts dragging it. */
  #press(at: Position, point: { x: number; y: number }): void {
    const f = this.state.mode === "select" ? this.#selectedFeature() : undefined;
    // Multi geometries (from a merge) are kept as they are.
    if (!f || f.geometry.type.startsWith("Multi")) return;
    const handle = this.#handle(f, point);
    if (!handle && this.#hit(point)?.id !== f.id) return;
    const map = this.#map;
    this.#drag = { at: null, from: at, before: this.state.features, pan: map.dragPan.isEnabled() };
    map.dragPan.disable();
    if (handle?.kind === "midpoint") {
      this.#replace(f.id, insertVertex(f.geometry, handle.at, handle.position));
      this.#drag.at = handle.at;
    } else if (handle) this.#drag.at = handle.at;
  }

  /** The vertex (first) or midpoint of `f` within `CLOSE_PIXELS` of `point`, nearest first. */
  #handle(f: DrawnFeature, point: { x: number; y: number }): { kind: "vertex" | "midpoint"; at: At; position: Position } | null {
    let best: { kind: "vertex" | "midpoint"; at: At; position: Position } | null = null;
    let dist = CLOSE_PIXELS;
    for (const [kind, list] of [["vertex", verticesOf(f.geometry)], ["midpoint", midpoints(f.geometry)]] as const) {
      for (const v of list) {
        const q = this.#screen(v.position);
        const d = Math.hypot(q.x - point.x, q.y - point.y);
        if (d < dist || (d <= dist && !best)) [dist, best] = [d, { kind, ...v }];
      }
      if (best) return best;
    }
    return best;
  }

  #dragTo(at: Position, point: { x: number; y: number }): void {
    const drag = this.#drag!;
    const f = this.#selectedFeature();
    if (!f) return;
    if (drag.at) return this.#replace(f.id, moveVertex(f.geometry, drag.at, this.#snap(at, point, f.id)));
    this.#replace(f.id, translate(f.geometry, at[0] - drag.from[0], at[1] - drag.from[1]));
    drag.from = at;
  }

  #release(): void {
    const drag = this.#drag;
    if (!drag) return;
    this.#drag = null;
    if (drag.pan) this.#map.dragPan.enable();
    if (this.state.features === drag.before) return;
    const features = this.state.features.map((f) => (f.id === this.state.selected ? { ...f, geometry: finished(f.geometry, this.#options.precision) } : f));
    this.#change(features, drag.before);
  }

  /** Right click on a vertex of the selected feature deletes it, while the shape keeps enough. */
  #unvertex(point: { x: number; y: number }): void {
    const f = this.state.mode === "select" ? this.#selectedFeature() : undefined;
    const handle = f && this.#handle(f, point);
    if (handle?.kind !== "vertex") return;
    const g = deleteVertex(f!.geometry, handle.at);
    if (g) this.#change(this.state.features.map((x) => (x.id === f!.id ? { ...x, geometry: g } : x)));
  }

  /** Feature `id` with `geometry`, shown at once and kept out of the history (a drag in progress). */
  #replace(id: string, geometry: DrawnFeature["geometry"]): void {
    this.#show({ features: this.state.features.map((f) => (f.id === id ? { ...f, geometry } : f)) });
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
    if (mode && mode !== "select" && vertices.length > 0) {
      const shape = mode === "split" ? "linestring" : mode;
      if (mode === "rectangle") drawing = p ? { type: "Polygon", coordinates: [rectangleRing(vertices[0], p)] } : null;
      else if (mode === "circle") drawing = this.#ring ? { type: "Polygon", coordinates: [this.#ring] } : null;
      else drawing = geometryOf(shape, mode === "freehand" || !p ? vertices : [...vertices, p]);
    }
    this.set({ drawing, canUndo: this.#done.length > 0 || vertices.length > 0, canRedo: this.#undone.length > 0 });
    const selection = this.state.selection;
    const shown: object[] = features.map((f) => ({ ...f, properties: { ...f.properties, kind: selection.includes(f.id) ? "selected" : "feature" } }));
    const sf = this.#selectedFeature();
    if (sf && /^(LineString|Polygon)$/.test(sf.geometry.type)) {
      const handle = (kind: string) => (v: { position: Position }) => ({ type: "Feature", properties: { kind }, geometry: { type: "Point", coordinates: v.position } });
      shown.push(...midpoints(sf.geometry).map(handle("midpoint")), ...verticesOf(sf.geometry).map(handle("vertex")));
    }
    if (drawing) shown.push({ type: "Feature", properties: { kind: "drawing" }, geometry: drawing });
    if (mode !== "freehand" && mode !== "select") for (const v of vertices) shown.push({ type: "Feature", properties: { kind: "vertex" }, geometry: { type: "Point", coordinates: v } });
    this.#map.getSource(this.#id)?.setData?.({ type: "FeatureCollection", features: shown });
  }

  #layers(): void {
    const map = this.#map;
    const id = this.#id;
    if (map.getSource(id)) return;
    const color = this.#options.color ?? "#3b6ed6";
    const selected = "#e4572e";
    const pick = ["case", ["==", ["get", "kind"], "selected"], selected, color];
    const metadata = { "mbmap:overlay": true };
    const kind = (k: string) => ["==", ["get", "kind"], k];
    const point = ["==", ["geometry-type"], "Point"];
    map.addSource(id, { type: "geojson", data: { type: "FeatureCollection", features: [] } });
    map.addLayer({ id: `${id}-fill`, type: "fill", source: id, filter: ["==", ["geometry-type"], "Polygon"], paint: { "fill-color": pick, "fill-opacity": 0.2 }, metadata });
    map.addLayer({ id: `${id}-line`, type: "line", source: id, filter: ["!=", ["geometry-type"], "Point"], paint: { "line-color": pick, "line-width": 2 }, metadata });
    map.addLayer({ id: `${id}-point`, type: "circle", source: id, filter: ["all", point, ["any", kind("feature"), kind("selected")]], paint: { "circle-color": pick, "circle-radius": 6, "circle-stroke-color": "#fff", "circle-stroke-width": 2 }, metadata });
    map.addLayer({ id: `${id}-midpoint`, type: "circle", source: id, filter: ["all", point, kind("midpoint")], paint: { "circle-color": selected, "circle-radius": 3, "circle-opacity": 0.6 }, metadata });
    map.addLayer({ id: `${id}-vertex`, type: "circle", source: id, filter: ["all", point, kind("vertex")], paint: { "circle-color": "#fff", "circle-radius": 4, "circle-stroke-color": color, "circle-stroke-width": 2 }, metadata });
  }

  #remove(): void {
    this.setMode(null);
    const map = this.#map;
    if (!map.getSource(this.#id)) return;
    for (const l of ["vertex", "midpoint", "point", "line", "fill"]) map.removeLayer(`${this.#id}-${l}`);
    map.removeSource(this.#id);
  }
}

/** The property that ties a piece of a split to its feature. */
const SOURCE = "mbmap:draw-source";

/** The selection without the ids `features` no longer has. */
function kept(features: DrawnFeature[], selection: string[]): Pick<DrawState, "selection" | "selected"> {
  const left = selection.filter((id) => features.some((f) => f.id === id));
  return { selection: left, selected: left.at(-1) ?? null };
}

function modeOf(type: string): DrawMode {
  return type.endsWith("Point") ? "point" : type.endsWith("LineString") ? "linestring" : "polygon";
}

export function createDraw(map: Map, options: DrawOptions = {}): Draw {
  return new DrawStore(map, options);
}
