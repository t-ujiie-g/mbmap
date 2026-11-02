// DOM over the map: the destinations as pins that follow their places with
// `Map.track` (faded where the terrain hides them), and the view saved as an image.
import { DESTINATIONS } from "./places.js";

/** Pins for the destinations in a layer added to `parent` (which covers the map); returns its removal. */
export function pinDestinations(map, parent) {
  const layer = document.createElement("div");
  layer.className = "pins";
  parent.append(layer);
  const trackers = DESTINATIONS.map((d) => {
    const pin = document.createElement("div");
    pin.className = "pin";
    pin.textContent = d.name;
    layer.append(pin);
    return map.track(d.center, ({ x, y, covered }) => {
      pin.style.transform = `translate(${x}px, ${y}px)`;
      pin.classList.toggle("covered", covered);
    });
  });
  window.__pins = layer;
  return () => {
    for (const t of trackers) t.remove();
    layer.remove();
  };
}

/** Saves the view as a PNG at twice the screen's resolution. */
export async function saveImage(map) {
  const blob = await map.toBlob({ pixelRatio: 2 });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = "mbmap.png";
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  window.__saved = { type: blob.type, size: blob.size };
}
