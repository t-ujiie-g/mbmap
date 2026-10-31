import { Map, type LngLat, type MapOptions, type StyleSpecification } from "mbmap";

/** `detail` of the events `<mb-map>` dispatches (they bubble and cross shadow roots). */
export interface MbMapEventDetail {
  /** Null only for an `mb-error` before the map exists. */
  map: Map | null;
  center: LngLat;
  zoom: number;
  error?: Error;
}

/** Strict `lng,lat`: two finite numbers within range, nothing else. */
export function parseCenter(value: string): LngLat | null {
  const m = /^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$/.exec(value);
  if (!m) return null;
  const lng = Number(m[1]);
  const lat = Number(m[2]);
  return Math.abs(lng) <= 180 && Math.abs(lat) <= 90 ? { lng, lat } : null;
}

/** Strict zoom: a decimal number from 0 to 24. */
export function parseZoom(value: string): number | null {
  if (!/^\s*\d+(?:\.\d+)?\s*$/.test(value)) return null;
  const z = Number(value);
  return z <= 24 ? z : null;
}

const ATTRIBUTES = ["style-url", "center", "zoom", "worker-count", "worker-url", "wasm-url"] as const;

// Lets the module load where HTMLElement does not exist (server rendering);
// the element is only defined in browsers.
const Base = (typeof HTMLElement === "undefined" ? class {} : HTMLElement) as typeof HTMLElement;

/**
 * `<mb-map style-url="..." center="139.76,35.68" zoom="12">`. The map lives in
 * the shadow root, so frameworks see one element whose content they never
 * touch. Invalid attribute values are rejected with an `mb-error` event, and
 * the previous value is kept. The style can also be set as the `mapStyle`
 * property (an object); `map` is the underlying `Map` once created.
 */
export class MbMapElement extends Base {
  static observedAttributes = ATTRIBUTES;

  #map: Map | null = null;
  #box: HTMLElement | null = null;
  #style: StyleSpecification | null = null;
  #center: LngLat = { lng: 0, lat: 0 };
  #zoom = 0;

  /** The underlying map, or null before it is created or after removal. */
  get map(): Map | null {
    return this.#map;
  }

  get mapStyle(): StyleSpecification | null {
    return this.#style;
  }

  /** A style object; takes precedence over `style-url` and recreates the map. */
  set mapStyle(style: StyleSpecification | null) {
    this.#style = style;
    this.#recreate();
  }

  get center(): LngLat {
    return this.#map?.getCenter() ?? { ...this.#center };
  }

  /** A `{lng, lat}` or the attribute form `"lng,lat"` (frameworks such as React set props as properties). */
  set center(center: LngLat | string) {
    const c = typeof center === "string" ? parseCenter(center) : center;
    if (!c || !Number.isFinite(c.lng) || !Number.isFinite(c.lat)) {
      this.#reject("center", String(center));
      return;
    }
    this.#center = { lng: c.lng, lat: c.lat };
    this.#map?.jumpTo({ center: this.#center });
  }

  get zoom(): number {
    return this.#map?.getZoom() ?? this.#zoom;
  }

  /** A number or the attribute form, from 0 to 24. */
  set zoom(value: number | string) {
    const zoom = typeof value === "string" ? parseZoom(value) : value;
    if (zoom === null || !Number.isFinite(zoom) || zoom < 0 || zoom > 24) {
      this.#reject("zoom", String(value));
      return;
    }
    this.#zoom = zoom;
    this.#map?.jumpTo({ zoom });
  }

  connectedCallback(): void {
    if (!this.#box) {
      const root = this.attachShadow({ mode: "open" });
      const style = document.createElement("style");
      style.textContent = ":host{display:block;position:relative}";
      // Inline, not a `div` rule: the map adds its own elements inside the box.
      this.#box = document.createElement("div");
      this.#box.style.cssText = "position:absolute;inset:0";
      root.append(style, this.#box);
    }
    if (!this.#map) this.#create();
  }

  disconnectedCallback(): void {
    // A move within the document disconnects and reconnects in one task;
    // keep the map then, and free it only if the element stays detached.
    queueMicrotask(() => {
      if (!this.isConnected) this.#destroy();
    });
  }

  attributeChangedCallback(name: (typeof ATTRIBUTES)[number], _old: string | null, value: string | null): void {
    if (value === null) return;
    if (name === "center") {
      this.center = value;
    } else if (name === "zoom") {
      this.zoom = value;
    } else if (name === "worker-count") {
      if (!/^[0-4]$/.test(value)) this.#reject(name, value);
    } else if (name === "style-url" && !this.#style) {
      this.#recreate();
    }
  }

  #reject(name: string, value: string): void {
    this.#dispatch("mb-error", new Error(`mb-map: invalid ${name}: ${JSON.stringify(value)}`));
  }

  #options(): Omit<MapOptions, "container"> | null {
    const style = this.#style ?? this.getAttribute("style-url");
    if (!style) return null;
    const count = this.getAttribute("worker-count");
    return {
      style,
      center: this.#center,
      zoom: this.#zoom,
      workerCount: count && /^[0-4]$/.test(count) ? Number(count) : 0,
      workerUrl: this.getAttribute("worker-url") ?? undefined,
      wasmUrl: this.getAttribute("wasm-url") ?? undefined,
    };
  }

  #create(): void {
    const options = this.#options();
    if (!options || !this.#box || !this.isConnected) return;
    let map: Map;
    try {
      map = new Map({ ...options, container: this.#box });
    } catch (err) {
      this.#dispatch("mb-error", err instanceof Error ? err : new Error(String(err)));
      return;
    }
    this.#map = map;
    map.on("load", () => this.#dispatch("mb-load"));
    map.on("idle", () => this.#dispatch("mb-idle"));
    map.on("move", () => this.#dispatch("mb-move"));
    map.on("error", (e) => this.#dispatch("mb-error", e.error));
  }

  #destroy(): void {
    if (!this.#map) return;
    // Keep the camera so that a re-attached element resumes where it was.
    this.#center = this.#map.getCenter();
    this.#zoom = this.#map.getZoom();
    this.#map.remove();
    this.#map = null;
  }

  #recreate(): void {
    this.#destroy();
    this.#create();
  }

  #dispatch(type: string, error?: Error): void {
    if (error) console.error(error);
    const map = this.#map;
    if (!map && !error) return;
    const detail: MbMapEventDetail = { map, center: this.center, zoom: this.zoom, ...(error ? { error } : {}) };
    this.dispatchEvent(new CustomEvent(type, { detail, bubbles: true, composed: true }));
  }
}

declare global {
  interface HTMLElementTagNameMap {
    "mb-map": MbMapElement;
  }
}

if (typeof customElements !== "undefined" && !customElements.get("mb-map")) {
  customElements.define("mb-map", MbMapElement);
}
