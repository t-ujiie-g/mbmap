// Zoom buttons, the compass and a home button without their look, as MapLibre's
// NavigationControl behaves.
import type { CameraOptions, Map } from "../index";
import { Store, type Controller } from "./controller";

/** The camera, and whether zooming in or out can go further (MapLibre disables its buttons at the limits). */
export interface NavigationState {
  zoom: number;
  bearing: number;
  pitch: number;
  canZoomIn: boolean;
  canZoomOut: boolean;
}

/** `home`: the camera `home()` goes to (by default the one when the controller was made). */
export interface NavigationOptions {
  home?: CameraOptions;
}

export interface Navigation extends Controller<NavigationState> {
  zoomIn(): void;
  zoomOut(): void;
  /** What a click on MapLibre's compass does: north up (and, with `pitch`, looking straight down). */
  resetNorth(pitch?: boolean): void;
  home(): void;
}

class NavigationController extends Store<NavigationState> implements Navigation {
  #map: Map;
  #home: CameraOptions;

  constructor(map: Map, options: NavigationOptions) {
    super(read(map));
    this.#map = map;
    this.#home = options.home ?? { center: map.getCenter(), zoom: map.getZoom(), bearing: map.getBearing(), pitch: map.getPitch() };
    this.listen(map, "move", () => this.set(read(map)));
  }

  zoomIn(): void {
    this.#map.zoomIn();
  }

  zoomOut(): void {
    this.#map.zoomOut();
  }

  resetNorth(pitch = false): void {
    if (pitch) this.#map.resetNorthPitch();
    else this.#map.resetNorth();
  }

  home(): void {
    this.#map.flyTo(this.#home);
  }
}

function read(map: Map): NavigationState {
  const zoom = map.getZoom();
  return {
    zoom,
    bearing: map.getBearing(),
    pitch: map.getPitch(),
    canZoomIn: zoom !== map.getMaxZoom(),
    canZoomOut: zoom !== map.getMinZoom(true),
  };
}

export function createNavigation(map: Map, options: NavigationOptions = {}): Navigation {
  return new NavigationController(map, options);
}
