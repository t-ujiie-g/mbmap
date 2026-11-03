// The user's location without its look, as MapLibre GL JS 6.16.0's
// GeolocateControl tracks it (its states, camera moves and accuracy circle;
// BSD-3-Clause, Copyright (c) 2020 MapLibre contributors; see NOTICE).
import type { FitBoundsOptions, LngLat, Map } from "../index";
import { Store, type Controller } from "./controller";
import { boundsAround, distanceTo } from "./measure";

/**
 * MapLibre's watch states, lower-cased: `off`, `waiting` (for a first position), `active` (the camera
 * follows), `background` (the user moved the map away), their `-error`s, and `unavailable` (no
 * Geolocation API, or permission denied).
 */
export type GeolocationStatus = "unavailable" | "off" | "waiting" | "active" | "active-error" | "background" | "background-error";

/**
 * `position`: the last one (null when off or out of `maxBounds`); `accuracyRadius`: its accuracy in
 * CSS pixels at the current camera, for drawing the circle; `error`: the last Geolocation error.
 */
export interface GeolocationState {
  status: GeolocationStatus;
  position: { lngLat: LngLat; accuracy: number; heading: number | null; timestamp: number } | null;
  accuracyRadius: number;
  error: { code: number; message: string } | null;
  outOfMaxBounds: boolean;
}

/**
 * As MapLibre's options: `positionOptions`, `fitBoundsOptions` (default `{ maxZoom: 15 }`),
 * `trackUserLocation` (default false: a one-off locate), `zoomToUserAccuracy` (default true);
 * `geolocation` replaces `navigator.geolocation` (for tests).
 */
export interface GeolocationOptions {
  positionOptions?: PositionOptions;
  fitBoundsOptions?: FitBoundsOptions;
  trackUserLocation?: boolean;
  zoomToUserAccuracy?: boolean;
  geolocation?: Geolocation;
}

export interface GeolocationController extends Controller<GeolocationState> {
  /** What a click on MapLibre's button does: locate once, or switch tracking on, off or back to active. */
  trigger(): boolean;
}

class GeolocationStore extends Store<GeolocationState> implements GeolocationController {
  #map: Map;
  #options: GeolocationOptions;
  #geo: Geolocation | undefined;
  #watch: number | undefined;
  #last: GeolocationPosition | null = null;
  // A camera move this controller started, and a move whose first step decides if it leaves `active`.
  #own = false;
  #pending: number | null = null;

  constructor(map: Map, options: GeolocationOptions) {
    const geo = options.geolocation ?? globalThis.navigator?.geolocation;
    super({ status: geo ? "off" : "unavailable", position: null, accuracyRadius: 0, error: null, outOfMaxBounds: false });
    this.#map = map;
    this.#options = options;
    this.#geo = geo;
    this.listen(map, "movestart", () => {
      if (!this.#own && this.state.status === "active") this.#pending = map.getZoom();
    });
    this.listen(map, "move", () => {
      // MapLibre keeps following while the zoom changes and lets go otherwise.
      if (this.#pending !== null && map.getZoom() === this.#pending) this.set({ status: "background" });
      this.#pending = null;
      this.#updateRadius();
    });
    this.listen(map, "moveend", () => {
      this.#own = false;
      this.#pending = null;
    });
    this.onDestroy(() => this.#clearWatch());
  }

  trigger(): boolean {
    const geo = this.#geo;
    if (!geo || this.state.status === "unavailable") return false;
    if (!this.#options.trackUserLocation) {
      geo.getCurrentPosition(this.#success, this.#failure, this.#positionOptions());
      return true;
    }
    switch (this.state.status) {
      case "off":
        this.set({ status: "waiting" });
        break;
      case "background":
        this.set({ status: "active" });
        if (this.#last) this.#moveCamera(this.#last);
        break;
      default:
        this.set({ status: "off", position: null, accuracyRadius: 0 });
    }
    if (this.state.status === "off") this.#clearWatch();
    else if (this.#watch === undefined) this.#watch = geo.watchPosition(this.#success, this.#failure, this.#positionOptions());
    return true;
  }

  #positionOptions(): PositionOptions {
    return this.#options.positionOptions ?? { enableHighAccuracy: false, maximumAge: 0, timeout: 6000 };
  }

  #clearWatch(): void {
    if (this.#watch !== undefined) this.#geo?.clearWatch(this.#watch);
    this.#watch = undefined;
  }

  #success = (p: GeolocationPosition): void => {
    const lngLat = { lng: p.coords.longitude, lat: p.coords.latitude };
    const b = this.#map.getMaxBounds();
    if (b && (lngLat.lng < b.west || lngLat.lng > b.east || lngLat.lat < b.south || lngLat.lat > b.north)) {
      this.#errorState();
      this.set({ position: null, accuracyRadius: 0, outOfMaxBounds: true });
      return;
    }
    const track = this.#options.trackUserLocation;
    const s = this.state.status;
    if (track) this.#last = p;
    this.set({
      status: !track ? s : s === "background" || s === "background-error" ? "background" : "active",
      position: { lngLat, accuracy: p.coords.accuracy, heading: p.coords.heading ?? null, timestamp: p.timestamp },
      error: null,
      outOfMaxBounds: false,
    });
    this.#updateRadius();
    if (!track || this.state.status === "active") this.#moveCamera(p);
  };

  #failure = (e: GeolocationPositionError): void => {
    const error = { code: e.code, message: e.message };
    if (e.code === 1) {
      // Permission denied: MapLibre turns off and disables its button.
      this.#clearWatch();
      this.set({ status: "unavailable", position: null, accuracyRadius: 0, error });
      return;
    }
    this.#errorState();
    this.set({ error });
  };

  #errorState(): void {
    const s = this.state.status;
    if (s === "waiting" || s === "active") this.set({ status: "active-error" });
    else if (s === "background") this.set({ status: "background-error" });
  }

  #moveCamera(p: GeolocationPosition): void {
    const center = { lng: p.coords.longitude, lat: p.coords.latitude };
    const bearing = this.#map.getBearing();
    const fit = this.#options.fitBoundsOptions ?? { maxZoom: 15 };
    this.#own = true;
    if (this.#options.zoomToUserAccuracy === false) {
      const options = { ...fit, center, bearing, zoom: this.#map.getZoom() };
      if (options.linear) this.#map.easeTo(options);
      else this.#map.flyTo(options);
    } else {
      this.#map.fitBounds(boundsAround(center, p.coords.accuracy), { bearing, ...fit });
    }
  }

  /** The accuracy circle's radius in CSS pixels, measured as MapLibre sizes its circle. */
  #updateRadius(): void {
    const pos = this.state.position;
    if (!pos) return;
    const at = this.#map.project(pos.lngLat);
    const metersPerPixel = distanceTo(pos.lngLat, this.#map.unproject([at.x + 100, at.y])) / 100;
    this.set({ accuracyRadius: pos.accuracy / metersPerPixel });
  }
}

export function createGeolocation(map: Map, options: GeolocationOptions = {}): GeolocationController {
  return new GeolocationStore(map, options);
}
