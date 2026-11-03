// The sources' attributions without their look (`attributionControl: false`
// hides the map's own), as MapLibre's AttributionControl lists them.
import type { Map } from "../index";
import { Store, type Controller } from "./controller";

/** `items`: the attribution texts, plain text (`customAttribution` first); `text`: joined with " | " as MapLibre shows them. */
export interface AttributionState {
  items: string[];
  text: string;
}

/** `customAttribution`: texts shown before the sources'. */
export interface AttributionOptions {
  customAttribution?: string | string[];
}

class AttributionStore extends Store<AttributionState> {
  constructor(map: Map, options: AttributionOptions) {
    const custom = options.customAttribution === undefined ? [] : [options.customAttribution].flat();
    const read = (): AttributionState => {
      const items = [...custom, ...map.getAttributions()];
      return { items, text: items.join(" | ") };
    };
    super(read());
    const update = () => {
      const next = read();
      if (next.text !== this.state.text) this.set(next);
    };
    this.listen(map, "styledata", update);
    this.listen(map, "zoom", update);
  }
}

export function createAttribution(map: Map, options: AttributionOptions = {}): Controller<AttributionState> {
  return new AttributionStore(map, options);
}
