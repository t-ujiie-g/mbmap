import { Map, type LngLat, type MapOptions, type StyleSpecification } from "mbmap";
import {
  checkBearing,
  checkCenter,
  checkPitch,
  checkZoom,
  parseBearing,
  parseCenter,
  parsePitch,
  parseWorkerCount,
  parseZoom,
} from "./parse";

export { MAX_PITCH, MAX_WORKERS, MAX_ZOOM, parseBearing, parseCenter, parsePitch, parseZoom } from "./parse";

/** `detail` of the events `<mb-map>` dispatches (they bubble and cross shadow roots); `map` is null only for an `mb-error` before the map exists. */
export interface MbMapEventDetail {
  map: Map | null;
  center: LngLat;
  zoom: number;
  bearing: number;
  pitch: number;
  error?: Error;
}

const ATTRIBUTES = ["style-url", "center", "zoom", "bearing", "pitch", "worker-count", "worker-url", "wasm-url"] as const;

// Lets the module load where HTMLElement does not exist (server rendering);
// the element is only defined in browsers.
const Base = (typeof HTMLElement === "undefined" ? class {} : HTMLElement) as typeof HTMLElement;

/**
 * `<mb-map style-url="..." center="139.76,35.68" zoom="12">`, the map in its
 * shadow root. Invalid attributes fire `mb-error` and keep the previous value;
 * `mapStyle` takes a style object and `map` is the `Map` once created.
 */
export class MbMapElement extends Base {
  static observedAttributes = ATTRIBUTES;

  #map: Map | null = null;
  #box: HTMLElement | null = null;
  #style: StyleSpecification | null = null;
  #center: LngLat = { lng: 0, lat: 0 };
  #zoom = 0;
  #bearing = 0;
  #pitch = 0;

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
    const c = typeof center === "string" ? parseCenter(center) : checkCenter(center);
    if (!c) {
      this.#reject("center", typeof center === "string" ? center : JSON.stringify(center));
      return;
    }
    this.#center = c;
    this.#map?.jumpTo({ center: this.#center });
  }

  get zoom(): number {
    return this.#map?.getZoom() ?? this.#zoom;
  }

  /** A number or the attribute form, from 0 to `MAX_ZOOM`. */
  set zoom(value: number | string) {
    const zoom = typeof value === "string" ? parseZoom(value) : checkZoom(value);
    if (zoom === null) {
      this.#reject("zoom", String(value));
      return;
    }
    this.#zoom = zoom;
    this.#map?.jumpTo({ zoom });
  }

  get bearing(): number {
    return this.#map?.getBearing() ?? this.#bearing;
  }

  /** Degrees clockwise from north, as a number or the attribute form. */
  set bearing(value: number | string) {
    const bearing = typeof value === "string" ? parseBearing(value) : checkBearing(value);
    if (bearing === null) {
      this.#reject("bearing", String(value));
      return;
    }
    this.#bearing = bearing;
    this.#map?.jumpTo({ bearing });
  }

  get pitch(): number {
    return this.#map?.getPitch() ?? this.#pitch;
  }

  /** Degrees of tilt from 0 to `MAX_PITCH`, as a number or the attribute form. */
  set pitch(value: number | string) {
    const pitch = typeof value === "string" ? parsePitch(value) : checkPitch(value);
    if (pitch === null) {
      this.#reject("pitch", String(value));
      return;
    }
    this.#pitch = pitch;
    this.#map?.jumpTo({ pitch });
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
    } else if (name === "bearing") {
      this.bearing = value;
    } else if (name === "pitch") {
      this.pitch = value;
    } else if (name === "worker-count") {
      if (parseWorkerCount(value) === null) this.#reject(name, value);
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
    return {
      style,
      center: this.#center,
      zoom: this.#zoom,
      bearing: this.#bearing,
      pitch: this.#pitch,
      workerCount: parseWorkerCount(this.getAttribute("worker-count") ?? "") ?? 0,
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
    this.#bearing = this.#map.getBearing();
    this.#pitch = this.#map.getPitch();
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
    const detail: MbMapEventDetail = {
      map,
      center: this.center,
      zoom: this.zoom,
      bearing: this.bearing,
      pitch: this.pitch,
      ...(error ? { error } : {}),
    };
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
