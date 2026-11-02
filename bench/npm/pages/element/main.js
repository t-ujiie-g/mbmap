// Registers <mb-map>; the element in the page then creates its map. Events
// are recorded for bench/npm/pack-test.mjs.
import "mbmap/element";

window.__events = [];
for (const type of ["mb-load", "mb-move", "mb-idle", "mb-error"]) {
  document.addEventListener(type, (e) => window.__events.push({ type, zoom: e.detail.zoom, error: e.detail.error?.message }));
}
document.addEventListener("mb-load", () => { window.__loaded = performance.now(); }, { once: true });
