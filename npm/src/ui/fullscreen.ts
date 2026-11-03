// Full screen without its look, as MapLibre's FullscreenControl: the Fullscreen
// API on the map's container, or where the browser has none a "pseudo" full
// screen the page styles itself.
import type { Map } from "../index";
import { Store, type Controller } from "./controller";

/** `active`: the container fills the screen; `pseudo`: without the Fullscreen API, the page should make it fill the window. */
export interface FullscreenState {
  active: boolean;
  pseudo: boolean;
}

/** `container`: what goes full screen (default the map's container). */
export interface FullscreenOptions {
  container?: HTMLElement;
}

export interface Fullscreen extends Controller<FullscreenState> {
  toggle(): void;
}

class FullscreenStore extends Store<FullscreenState> implements Fullscreen {
  #container: HTMLElement;

  constructor(map: Map, options: FullscreenOptions) {
    super({ active: false, pseudo: !document.fullscreenEnabled });
    this.#container = options.container ?? map.getContainer();
    const change = () => this.set({ active: document.fullscreenElement === this.#container });
    document.addEventListener("fullscreenchange", change);
    this.onDestroy(() => document.removeEventListener("fullscreenchange", change));
  }

  toggle(): void {
    if (this.state.pseudo) this.set({ active: !this.state.active });
    else if (this.state.active) void document.exitFullscreen();
    else void this.#container.requestFullscreen();
  }
}

export function createFullscreen(map: Map, options: FullscreenOptions = {}): Fullscreen {
  return new FullscreenStore(map, options);
}
