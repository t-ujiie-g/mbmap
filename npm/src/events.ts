// The map's event listeners: its own events, and mouse events on layers' features.
import type { Map } from "./index";
import type { MapEvent, MapEventListener, MapEventType, MapGeoJSONFeature, MapMouseEventType } from "./types";

type Point = { x: number; y: number };

interface LayerListener {
  type: MapMouseEventType;
  layers: string[];
  listener: MapEventListener;
  inside: boolean;
}

const hover = (l: { type: MapMouseEventType }) => l.type === "mouseenter" || l.type === "mouseleave";

export class Events {
  #target: Map;
  #query: (point: Point, layers: string[]) => Promise<MapGeoJSONFeature[]>;
  #listeners = new globalThis.Map<MapEventType, Set<MapEventListener>>();
  #layers: LayerListener[] = [];
  #mouseDown: Point | null = null;
  #hovering = false;
  #nextHover: { e: MouseEvent; p: Point } | null = null;
  #closed = false;

  /** `query` finds the features of `layers` drawn at a point, for listeners on layers. */
  constructor(target: Map, query: (point: Point, layers: string[]) => Promise<MapGeoJSONFeature[]>) {
    this.#target = target;
    this.#query = query;
  }

  has(type: MapEventType): boolean {
    return !!this.#listeners.get(type)?.size;
  }

  on(type: MapEventType, a: MapEventListener | string | string[], b?: MapEventListener): void {
    if (typeof a === "function") {
      let set = this.#listeners.get(type);
      if (!set) this.#listeners.set(type, (set = new Set()));
      set.add(a);
    } else if (b) {
      this.#layers.push({ type: type as MapMouseEventType, layers: Array.isArray(a) ? [...a] : [a], listener: b, inside: false });
    }
  }

  off(type: MapEventType, a: MapEventListener | string | string[], b?: MapEventListener): void {
    if (typeof a === "function") {
      this.#listeners.get(type)?.delete(a);
      return;
    }
    const ids = Array.isArray(a) ? a : [a];
    const same = (l: LayerListener) => l.type === type && l.listener === b && l.layers.length === ids.length && l.layers.every((id, i) => id === ids[i]);
    this.#layers = this.#layers.filter((l) => !same(l));
  }

  /** Listens for the next `type` event (on `layers`' features if `a` names them); without a listener, a Promise of it. */
  once(type: MapEventType, a?: MapEventListener | string | string[], b?: MapEventListener): Promise<MapEvent> | undefined {
    const layers = typeof a === "function" ? undefined : a;
    const listener = typeof a === "function" ? a : b;
    if (!listener) return new Promise((resolve) => (layers === undefined ? this.once(type, resolve) : this.once(type, layers, resolve)));
    const wrapped: MapEventListener = (e) => {
      if (layers === undefined) this.off(type, wrapped);
      else this.off(type, layers, wrapped);
      listener(e);
    };
    if (layers === undefined) this.on(type, wrapped);
    else this.on(type, layers, wrapped);
  }

  emit(type: MapEventType, error?: Error, originalEvent?: Event | null, id?: string): void {
    const event: MapEvent = { type, target: this.#target };
    if (error) event.error = error;
    if (originalEvent) event.originalEvent = originalEvent;
    if (id !== undefined) event.id = id;
    this.#fire(event, this.#listeners.get(type) ?? []);
  }

  #fire(event: MapEvent, listeners: Iterable<MapEventListener>): void {
    for (const f of [...listeners]) {
      try {
        f(event);
      } catch (err) {
        // Report without breaking the engine's frame.
        queueMicrotask(() => {
          throw err;
        });
      }
    }
  }

  #mouseEvent(type: MapMouseEventType, e: MouseEvent, p: Point, features?: MapGeoJSONFeature[]): MapEvent {
    const event: MapEvent = { type, target: this.#target, originalEvent: e, point: p, lngLat: this.#target.unproject(p) };
    if (features) event.features = features;
    return event;
  }

  /**
   * A DOM mouse event on the canvas: the map's own (a click only after less than 3 px of movement),
   * then the layers' listeners once a query finds their features (`mouseenter` and `mouseleave`
   * follow `mousemove` and `mouseout`), as in MapLibre.
   */
  mouse(type: Exclude<MapMouseEventType, "mouseenter" | "mouseleave">, e: MouseEvent, p: Point): void {
    if (type === "mousedown") this.#mouseDown = p;
    if (type === "click" && this.#mouseDown && Math.hypot(p.x - this.#mouseDown.x, p.y - this.#mouseDown.y) >= 3) return;
    this.#fire(this.#mouseEvent(type, e, p), this.#listeners.get(type) ?? []);
    if (type === "mouseout") {
      for (const l of this.#layers) {
        if (!hover(l) || !l.inside) continue;
        l.inside = false;
        if (l.type === "mouseleave") this.#fire(this.#mouseEvent("mouseleave", e, p), [l.listener]);
      }
    }
    const asked = this.#layers.filter((l) => l.type === type || (type === "mousemove" && hover(l)));
    if (asked.length === 0) return;
    if (type === "mousemove") {
      // One query at a time; moves in between keep only the latest.
      if (this.#hovering) {
        this.#nextHover = { e, p };
        return;
      }
      this.#hovering = true;
    }
    const layers = [...new Set(asked.flatMap((l) => l.layers))].filter((id) => this.#target.getLayer(id));
    const found = layers.length === 0 ? Promise.resolve([]) : this.#query(p, layers);
    found
      .catch(() => [] as MapGeoJSONFeature[])
      .then((features) => {
        for (const l of asked) {
          const mine = features.filter((f) => l.layers.includes(f.layer.id));
          if (l.type === type) {
            if (mine.length > 0) this.#fire(this.#mouseEvent(type, e, p, mine), [l.listener]);
          } else if (mine.length > 0 && !l.inside) {
            l.inside = true;
            if (l.type === "mouseenter") this.#fire(this.#mouseEvent("mouseenter", e, p, mine), [l.listener]);
          } else if (mine.length === 0 && l.inside) {
            l.inside = false;
            if (l.type === "mouseleave") this.#fire(this.#mouseEvent("mouseleave", e, p), [l.listener]);
          }
        }
        if (type !== "mousemove") return;
        this.#hovering = false;
        const next = this.#nextHover;
        this.#nextHover = null;
        if (next && !this.#closed) this.mouse("mousemove", next.e, next.p);
      });
  }

  /** Drops every listener; queries still under way fire nothing more. */
  clear(): void {
    this.#closed = true;
    this.#listeners.clear();
    this.#layers = [];
  }
}
