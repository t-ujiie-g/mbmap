// A glTF model through mbmap/3d: a clock tower (tower.glb, meshopt-compressed) on Gyoko-dori in front
// of Tokyo Station, under the places. A new style drops custom layers, so it goes back each time.
import { modelLayer } from "mbmap/3d";

const TOWERS = {
  type: "FeatureCollection",
  features: [{ type: "Feature", properties: { heading: 0 }, geometry: { type: "Point", coordinates: [139.7643, 35.6814] } }],
};

/** Keeps the tower layer `models` on `map` across style changes. */
export function keepModels(map) {
  const layer = modelLayer({ id: "models", model: new URL("../shared/tower.glb", location.href).href, data: TOWERS, rotation: [0, 0, ["get", "heading"]] });
  const add = () => {
    if (map.getStyle() && !map.getLayer("models")) map.addLayer(layer, map.getLayer("places") ? "places" : undefined);
  };
  map.on("styledata", add);
  add();
  return layer;
}
